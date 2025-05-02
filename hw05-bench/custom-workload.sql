\set aid random(1, 100000)
SELECT aid, abalance
FROM pgbench_accounts
WHERE aid BETWEEN :aid AND (:aid + 100)
ORDER BY abalance DESC
    LIMIT 5;

\set aid random(1, 100000)
SELECT COUNT(*)
FROM pgbench_accounts
WHERE abalance > 0;

\set aid random(1, 100000)
SELECT AVG(abalance)
FROM pgbench_accounts
WHERE aid BETWEEN :aid AND (:aid + 500);

\set aid random(1, 100000)
SELECT aid
FROM pgbench_accounts
ORDER BY aid DESC
    LIMIT 10;

\set aid random(1, 100000)
SELECT aid, abalance
FROM pgbench_accounts
WHERE aid = :aid;

\set tid random(1, 10)
\set bid random(1, 10)
\set aid random(1, 100000)
\set delta random(-5000, 5000)
INSERT INTO pgbench_history (tid, bid, aid, delta, mtime)
VALUES (:tid, :bid, :aid, :delta, CURRENT_TIMESTAMP);