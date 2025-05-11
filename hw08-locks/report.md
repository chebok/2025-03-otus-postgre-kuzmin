## Шаг 0: Конфигурирование pg-кластера
Настройка пгкластера для отслеживания блокировок в журнале:
- log_lock_waits = on
- deadlock_timeout = 200ms

Подготовка тестовой таблицы с данными
```sql
CREATE TABLE locks_test (
    id INT PRIMARY KEY,
    value TEXT
);
INSERT INTO locks_test VALUES (1, 'initial');
```

## Шаг 1: Воспроизводим блокировки

Запускаем две сессии и пытаемся обновить одну и ту же строку:
Сессия1
```sql
begin;
update locks_test set value = 'session1' where id = 1;
```
Сессия2
```sql
begin;
update locks_test set value = 'session2' where id = 1;
```

Далее коммитим транзакции, проверяем логи и фиксируем локи
```
2025-05-11 15:18:40.504 UTC [469208] postgres@postgres LOG:  process 469208 still waiting for ShareLock on transaction 951493 after 200.103 ms
2025-05-11 15:18:40.504 UTC [469208] postgres@postgres DETAIL:  Process holding the lock: 469082. Wait queue: 469208.
2025-05-11 15:18:40.504 UTC [469208] postgres@postgres CONTEXT:  while updating tuple (0,1) in relation "locks_test"
2025-05-11 15:18:40.504 UTC [469208] postgres@postgres STATEMENT:  UPDATE locks_test SET value = 'session2' WHERE id = 1;
2025-05-11 15:19:09.635 UTC [469208] postgres@postgres LOG:  process 469208 acquired ShareLock on transaction 951493 after 29331.818 ms
2025-05-11 15:19:09.635 UTC [469208] postgres@postgres CONTEXT:  while updating tuple (0,1) in relation "locks_test"
2025-05-11 15:19:09.635 UTC [469208] postgres@postgres STATEMENT:  UPDATE locks_test SET value = 'session2' WHERE id = 1;
```

## Шаг 2: Три сессии и pg_locks

Запускаем три сессии и пытаемся обновить одну и ту же строку:
```sql
update locks_test set value = 'session1' where id = 1;
update locks_test set value = 'session2' where id = 1;
update locks_test set value = 'session3' where id = 1;
```

Смотри pg_locks:
```sql
SELECT pid, locktype, relation::regclass, mode, granted, transactionid
FROM pg_locks
WHERE relation IS NOT NULL OR transactionid IS NOT NULL
ORDER BY granted, pid;
```

Анализ блокировок при одновременных UPDATE одной строки:

1. **Первая транзакция (pid 469082)**:
    - Захватила `RowExclusiveLock` на таблицу и индекс
    - Владеет транзакцией `951498` (строка ссылается на неё через XMIN)
    - Никого не ждёт

2. **Вторая транзакция (pid 469208)**:
    - Пытается получить `ShareLock` на `transactionid 951498`
    - Это значит: ждёт завершения первой транзакции
    - Также поставила `ExclusiveLock` на строку (locktype = tuple) — это означает, что она хочет модифицировать конкретную строку.
    - Уже захватила `RowExclusiveLock` на таблицу, но не может продолжить `UPDATE`

3. **Третья транзакция (pid 470317)**:
    - Не может получить `ExclusiveLock` на строку (tuple)
    - Ждёт завершения предыдущих
    - Почему-то нет `ShareLock`

Таким образом, `pg_locks` позволяет увидеть как блокировки происходят на уровне таблицы, строки и транзакции.

## Шаг 3: Воспроизводим дедлоки

Подготовка тестовой таблицы с данными
```sql
CREATE TABLE deadlock_test (
   id INT PRIMARY KEY,
   value TEXT
);
INSERT INTO deadlock_test VALUES (1, 'a'), (2, 'b'), (3, 'c');
```

Запускаем три сессии и пытаемся обновляем по одной строке в каждой из них:
```sql
UPDATE deadlock_test SET value = 'A' WHERE id = 1;
UPDATE deadlock_test SET value = 'B' WHERE id = 2;
UPDATE deadlock_test SET value = 'C' WHERE id = 3;
```

Далее смещаемся на одну строку и снова пытаемся обновить в разных сессиях:
```sql
UPDATE deadlock_test SET value = 'A' WHERE id = 2;
UPDATE deadlock_test SET value = 'B' WHERE id = 3;
UPDATE deadlock_test SET value = 'C' WHERE id = 1;
```

Ловим ошибку в третей сессии 
```
ERROR: deadlock detected
DETAIL: 
  Process 469208 waits for ShareLock on transaction 951503; blocked by process 469082.
  Process 469082 waits for ShareLock on transaction 951504; blocked by process 470317.
  Process 470317 waits for ShareLock on transaction 951505; blocked by process 469208.
```

Взаимоблокировка 3 транзакций — анализ по журналу PostgreSQL
```bash
sudo tail -n 100 /var/log/postgresql/postgresql-16-main.log
```
PostgreSQL сам детектирует взаимоблокировку между тремя транзакциями.  
В логе можно увидеть цепочку ожиданий:
- Process A → ждёт транзакцию B
- Process B → ждёт транзакцию C
- Process C → ждёт транзакцию A

Это кольцо ожиданий, которое PostgreSQL детектирует как deadlock.  
Он автоматически завершает одну транзакцию и пишет в лог:
> `ERROR: deadlock detected`  
> `DETAIL: Process ... waits for ShareLock on transaction ...`  
> `CONTEXT: while updating tuple (0,X) in relation "deadlock_test"`
> 
Таким образом, по логу можно чётко восстановить всю картину блокировок.

## Шаг 4: Имитация реалистичных сценариев для дедлока

Подготовка тестовой таблицы с данными
```sql
CREATE TABLE accounts (
   id INT PRIMARY KEY,
   balance INT NOT NULL
);
INSERT INTO accounts VALUES (1, 1000), (2, 1000);
```

Запускаем две сессии и пытаем изменить сумму на счете по разным id
```sql
UPDATE accounts SET balance = balance - 100 WHERE id = 1;
UPDATE accounts SET balance = balance - 50 WHERE id = 2;
```

Далее пытаем закинуть эти суммы на другие аккаунты
```sql
UPDATE accounts SET balance = balance + 100 WHERE id = 2;
UPDATE accounts SET balance = balance + 50 WHERE id = 1;
```

Ловим ошибку
```
ERROR:  deadlock detected
DETAIL: Process 470317 waits for ShareLock on transaction 951509; blocked by process 469082.
        Process 469082 waits for ShareLock on transaction 951510; blocked by process 470317.
HINT:   See server log for query details.
CONTEXT: while updating tuple (0,1) in relation "accounts"
```

Пытаемся сделать захват строк через SELECT FOR UPDATE в каждой сессии перед попытками обнволения
```sql
SELECT id, balance
FROM accounts
WHERE id IN (1, 2)
ORDER BY id
FOR UPDATE;
```

Пытаем обновить балансы аккаунтов, никаких проблем нет дедлоки отсутствуют

| PID    | Тип           | Объект         | Mode                | granted      |
| ------ | ------------- | -------------- | ------------------- | ------------ |
| 469082 | relation      | accounts       | RowExclusiveLock    | ✅            |
| 469082 | relation      | accounts\_pkey | RowExclusiveLock    | ✅            |
| 469082 | transactionid |                | ExclusiveLock       | ✅            |
| 470317 | relation      | accounts       | RowShareLock        | ✅            |
| 470317 | relation      | accounts\_pkey | RowShareLock        | ✅            |
| 470317 | tuple         | accounts (0,1) | AccessExclusiveLock | ✅            |
| 470317 | transactionid |                | ShareLock           | ❌ (ожидание) |

Итог по `SELECT FOR UPDATE` и `RowShareLock`

- `SELECT ... FOR UPDATE` ставит `RowShareLock` на таблицу — сигнал о намерении обновить строки.
- Для выбранных строк захватывается `AccessExclusiveLock` (tuple).
- Остальные строки не блокируются — другие транзакции могут работать с другими ID.

Почему `RowShareLock`, а не `RowExclusiveLock`

- `RowShareLock` — слабая блокировка, ставится `SELECT FOR UPDATE`.
- `RowExclusiveLock` появляется только при `UPDATE` — это уже реальное изменение данных.

