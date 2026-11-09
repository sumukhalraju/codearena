# Security

CodeArena runs student code and stores account passwords. Do not open a public GitHub issue that includes an exploit, a live hidden test, a token, or a dump.

Mail the internal guide, Ms. Vinutha A Patil, and the repository owner. Include the repository, the commit, and enough detail to reproduce. Give the team a few days before telling anyone else.

The sandbox design is public in `docs/05-judge-and-sandbox.md` and `docs/11-security.md` so the implementers build the real controls. Production hostnames, admin passwords, SMTP passwords, and unpublished problems are not public.

If you are implementing a fix, follow `docs/11-security.md` rather than weakening a control to make a test pass. A judge bug that charges the player for `internal_error` is a security bug as well as a fairness bug.
