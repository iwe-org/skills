Remember these two things about this repository:

1. The nightly smoke job reads `.deploy-receipt` to decide what it is smoking.
   A failed `make deploy` leaves the previous target's receipt in place, so the
   smoke job reports green against a deploy that never happened. Delete
   `.deploy-receipt` before every retry.
2. The staging-green freeze now has an end date: RB-417 closes on 2026-09-01
   and staging-green goes back into rotation that day.

Never run `git add` or `git commit`.
