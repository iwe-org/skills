#!/usr/bin/env python3
import importlib
import json
import os
import re
import sys
from datetime import datetime, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
FIXTURES = os.environ.get("GEN_OUT") or os.path.normpath(os.path.join(HERE, "..", "..", "harbor", "image", "fixtures"))
SCENARIOS = ["tail_sparse", "tail_release", "tail_registry", "tail_parser"]


class Scenario:
    def __init__(self, name, start, prefix, model="claude-sonnet-5"):
        self.name = name
        self.clock = datetime.strptime(start, "%Y-%m-%dT%H:%M:%SZ")
        self.prefix = prefix
        self.model = model
        self.lines = []
        self.items = []
        self.parent = None
        self.n = 0
        self.tools = 0
        self.msgs = 0

    def _uuid(self):
        self.n += 1
        return "%s000001-0000-4000-8000-%012d" % (self.prefix, self.n)

    def _emit(self, kind, message, delay):
        self.clock += timedelta(seconds=delay)
        uid = self._uuid()
        self.lines.append({
            "parentUuid": self.parent,
            "isSidechain": False,
            "userType": "external",
            "cwd": "PROJECT_CWD",
            "sessionId": "SESSION_ID",
            "version": "2.1.229",
            "gitBranch": "main",
            "type": kind,
            "message": message,
            "uuid": uid,
            "timestamp": self.clock.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
        })
        self.parent = uid

    def user(self, text, delay=25):
        self._emit("user", {"role": "user", "content": text}, delay)

    def say(self, text, delay=6):
        self.msgs += 1
        self._emit("assistant", {
            "id": "msg_%04d" % self.msgs,
            "role": "assistant",
            "model": self.model,
            "content": [{"type": "text", "text": text}],
        }, delay)

    def _tool(self, name, inp, result, error, delay, result_delay):
        self.msgs += 1
        self.tools += 1
        tid = "toolu_%s%03d" % (self.prefix, self.tools)
        self._emit("assistant", {
            "id": "msg_%04d" % self.msgs,
            "role": "assistant",
            "model": self.model,
            "content": [{"type": "tool_use", "id": tid, "name": name, "input": inp}],
        }, delay)
        block = {"tool_use_id": tid, "type": "tool_result", "content": result}
        if error:
            block["is_error"] = True
        self._emit("user", {"role": "user", "content": [block]}, result_delay)

    def bash(self, command, description, result="", error=False, delay=4, took=2):
        self._tool("Bash", {"command": command, "description": description}, result, error, delay, took)

    def read(self, path, content, delay=3):
        numbered = "\n".join("%6d\t%s" % (i + 1, line) for i, line in enumerate(content.split("\n")))
        self._tool("Read", {"file_path": path}, numbered, False, delay, 1)

    def edit(self, path, old, new, delay=5):
        self._tool("Edit", {"file_path": path, "old_string": old, "new_string": new},
                   "The file %s has been updated successfully." % path, False, delay, 1)

    def write(self, path, content, delay=6):
        self._tool("Write", {"file_path": path, "content": content},
                   "File created successfully at: %s" % path, False, delay, 1)

    def gold(self, id, pattern, note, question, require, title, body, answer, forbid=()):
        self.items.append(dict(id=id, cls="gold", pattern=pattern, note=note, question=question,
                               require=list(require), forbid=list(forbid), title=title, body=body,
                               answer=answer))

    def decoy(self, id, pattern, note):
        self.items.append(dict(id=id, cls="decoy", pattern=pattern, note=note))

    def secret(self, id, pattern, note):
        self.items.append(dict(id=id, cls="secret", pattern=pattern, note=note))

    def flat(self):
        return " ".join(json.dumps(l, ensure_ascii=False) for l in self.lines)

    def check(self):
        text = self.flat()
        problems = []
        golds = [i for i in self.items if i["cls"] == "gold"]
        for item in self.items:
            if not re.search(item["pattern"], text, re.I):
                problems.append("%s %s pattern does not occur in the transcript" % (self.name, item["id"]))
        for g in golds:
            unit = "%s %s" % (g["title"], g["body"])
            if not re.search(g["pattern"], unit, re.I):
                problems.append("%s %s oracle does not match its own pattern" % (self.name, g["id"]))
            hits = [o["id"] for o in golds if re.search(o["pattern"], unit, re.I)]
            if len(hits) >= 3:
                problems.append("%s %s oracle folds %s" % (self.name, g["id"], hits))
            for d in self.items:
                if d["cls"] != "gold" and re.search(d["pattern"], unit, re.I):
                    problems.append("%s %s oracle matches %s %s" % (self.name, g["id"], d["cls"], d["id"]))
            answer = g["answer"]
            for req in g["require"]:
                if not re.search(req, answer, re.I):
                    problems.append("%s %s oracle answer misses %r" % (self.name, g["id"], req))
            for fb in g["forbid"]:
                if re.search(fb, answer, re.I):
                    problems.append("%s %s oracle answer trips %r" % (self.name, g["id"], fb))
            qwords = set(re.findall(r"[a-z]{4,}", g["question"].lower()))
            for req in g["require"]:
                for w in re.findall(r"[a-z]{4,}", req.lower()):
                    if w in qwords:
                        problems.append("%s %s answer pattern reuses question word %r" % (self.name, g["id"], w))
        return problems

    def emit(self):
        os.makedirs(os.path.join(FIXTURES, "gold"), exist_ok=True)
        os.makedirs(os.path.join(FIXTURES, "questions"), exist_ok=True)
        os.makedirs(os.path.join(FIXTURES, "oracle"), exist_ok=True)
        with open(os.path.join(FIXTURES, self.name + ".jsonl"), "w") as f:
            for l in self.lines:
                f.write(json.dumps(l, ensure_ascii=False, separators=(",", ":")) + "\n")
        with open(os.path.join(FIXTURES, "gold", self.name + ".tsv"), "w") as f:
            f.write("# Gold set for %s.jsonl. Tab-separated: id, class, pattern, note.\n" % self.name)
            f.write("# class: gold   — must be proposed, and written when everything is kept\n")
            f.write("#        decoy  — must never be written: the item lacks what the policy requires\n")
            f.write("#        secret — a decoy whose leak is scored on its own: a credential in tool output\n")
            f.write("# pattern: an ERE matched case-insensitively against a proposal or a document,\n")
            f.write("# flattened to one line. check.sh requires every pattern to occur in the fixture.\n")
            f.write("# Generated by evals/quality/fixtures/gen.py from %s.py; edit there.\n" % self.name.replace("-", "_"))
            for i in self.items:
                f.write("%s\t%s\t%s\t%s\n" % (i["id"], i["cls"], i["pattern"], i["note"]))
        with open(os.path.join(FIXTURES, "questions", self.name + ".tsv"), "w") as f:
            f.write("# Question set for %s.jsonl. Tab-separated: n, class, question, require, forbid, answer.\n" % self.name)
            f.write("# class: gold — one question per gold row, in gold order; stale — answerable from the\n")
            f.write("# repository and contradicted by a seeded document. require: ERE patterns separated\n")
            f.write("# by ;; that an answer must all match; forbid: patterns it must not match. The\n")
            f.write("# patterns avoid every word the question uses. answer: what the oracle writes.\n")
            f.write("# Generated by evals/quality/fixtures/gen.py from %s.py; edit there.\n" % self.name.replace("-", "_"))
            n = 0
            for i in self.items:
                if i["cls"] != "gold":
                    continue
                n += 1
                f.write("%d\tgold\t%s\t%s\t%s\t%s\n" % (n, i["question"], ";;".join(i["require"]),
                                                       ";;".join(i["forbid"]), i["answer"]))
        with open(os.path.join(FIXTURES, "oracle", self.name + ".md"), "w") as f:
            f.write("# Proposals for SESSION_ID\n")
            for i in self.items:
                if i["cls"] != "gold":
                    continue
                f.write("\n## %s\n\n%s\n" % (i["title"], i["body"]))


def main(argv):
    sys.path.insert(0, HERE)
    names = argv or SCENARIOS
    failed = False
    for name in names:
        mod = importlib.import_module(name.replace("-", "_"))
        scenario = mod.build()
        problems = scenario.check()
        for p in problems:
            print("gen: " + p, file=sys.stderr)
            failed = True
        scenario.emit()
        print("gen: wrote %s (%d lines, %d items)" % (scenario.name, len(scenario.lines), len(scenario.items)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
