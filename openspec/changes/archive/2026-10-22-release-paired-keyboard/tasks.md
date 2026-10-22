## 1. Implementation

- [ ] 1.1 Expose whether the selected keyboard is paired locally and notify ownership when it changes
- [ ] 1.2 Release a paired keyboard, connected or not, when release is required and on keyboard reconfiguration

## 2. Verification

- [ ] 2.1 Add checks for releasing a paired-but-disconnected keyboard, including after Bluetooth returns, and for keeping it while this Mac should own it
- [x] 2.2 Install on this Mac and confirm normal hand-overs still work
