## 1. Regression Coverage

- [x] 1.1 Add storage-catalog assertions for non-null run lifecycle columns and
  the scoped descending keyset index
- [x] 1.2 Add runtime assertions that every production Oban worker has a finite
  deadline below the Lifeline rescue threshold

## 2. Run Storage

- [x] 2.1 Add a forward migration that backfills unknown lifecycle state,
  enforces non-null columns, and creates the composite run index
- [x] 2.2 Align the Ash Run resource with the non-null storage contract

## 3. Durable Job Runtime

- [x] 3.1 Add explicit deadlines to every production Oban worker
- [x] 3.2 Raise the Lifeline threshold above the maximum worker deadline

## 4. Verification And Closeout

- [x] 4.1 Run focused tests, formatting, strict OpenSpec validation, and the
  full repository verification gate
- [x] 4.2 Sync the durable specs and archive the completed OpenSpec change
