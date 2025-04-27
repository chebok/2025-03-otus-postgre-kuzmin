## Шаг 0: Подготовка тестового стенда
Тестирование проводится на виртуальной машине в Яндекс Облаке со следующими параметрами:
- Платформа: Intel Ice Lake
- vCPU: 2 ядра
- RAM: 4 ГБ
- Диск: ssd 10 ГБ,
- ОС: Ubuntu 22.04 LTS
- Postgres 16-й

## Шаг 1: Тест на дефолтной конфигурации

Инициализация тестовой базы и запуск теста:
```bash
sudo -i -u postgres
pgbench -i -U postgres postgres
pgbench -c8 -P 6 -T 60 -U postgres postgres
```
Результат
- Количество клиентов: 8
- Количество потоков: 1
- Длительность теста: 60 секунд
- Общее количество выполненных транзакций: 12441
- Количество ошибок: 0 (0.000%)
- Средняя latency транзакции: 38.550 ms
- Пропускная способность (TPS): 207.359525 транзакций/секунду (без учета времени подключения)

## Шаг 2: Тест на подготовленной конфигурации

Применяем конфигурацию из дз:
- max_connections = 40
- shared_buffers = 1GB
- effective_cache_size = 3GB
- maintenance_work_mem = 512MB
- checkpoint_completion_target = 0.9
- wal_buffers = 16MB
- default_statistics_target = 500
- random_page_cost = 4
- effective_io_concurrency = 2
- work_mem = 6553kB
- min_wal_size = 4GB
- max_wal_size = 16GB

Результат
- Количество клиентов: 8
- Количество потоков: 1
- Длительность теста: 60 секунд
- Общее количество выполненных транзакций: 11342
- Количество ошибок: 0 (0.000%)
- Средняя latency транзакции: 42.310 ms
- Пропускная способность (TPS): 188.811288 транзакций/секунду (без учета времени подключения)

Вывод: видим уменьшение производительности, так как выставили слишком агрессивные настройки по памяти для нашей вм. Они завышены для наших ресурсов.

## Шаг 3: Автовакуум

- Создание тестовый таблицы и заполнение данными
```sql
CREATE TABLE test_table (
  id SERIAL PRIMARY KEY,
  data TEXT
);
INSERT INTO test_table (data)
SELECT md5(random()::text)
FROM generate_series(1, 1000000);
```

- Размер таблицы 87 MB
```sql
SELECT pg_size_pretty(pg_total_relation_size('test_table'));
```

- Обновляем все строки 5 раз
```sql
UPDATE test_table
SET data = data || '#';
```

- Проверяем количество мертвых строк и разбер таблицы
```
postgres=# SELECT relname, n_live_tup, n_dead_tup, last_autovacuum FROM pg_stat_user_tables WHERE relname = 'test_table';
  relname   | n_live_tup | n_dead_tup |        last_autovacuum        
------------+------------+------------+-------------------------------
 test_table |    1000000 |    1000000 | 2025-04-27 12:08:42.388627+00
(1 row)

postgres=# SELECT pg_size_pretty(pg_total_relation_size('test_table'));                   
 pg_size_pretty 
----------------
 283 MB
(1 row)
```
Вывод: автовакуум почистил метаданные, но при этом размер не уменьшил

- Еще раз обновляем строки 5 раз
- Снова проверяем количество мертвых строк и разбер таблицы
```
postgres=# SELECT relname, n_live_tup, n_dead_tup, last_autovacuum FROM pg_stat_user_tables WHERE relname = 'test_table';
  relname   | n_live_tup | n_dead_tup |        last_autovacuum        
------------+------------+------------+-------------------------------
 test_table |    1000000 |     999895 | 2025-04-27 12:18:40.546363+00
(1 row)

postgres=# SELECT pg_size_pretty(pg_total_relation_size('test_table'));                                                  
 pg_size_pretty 
----------------
 265 MB
(1 row)
```
Вывод: автовакуум еще раз отработал, видимо попались какие-то страницы пустые и он их удалил

## Шаг 4: Без автовакуума

- Отключаем автовакуум
```sql
ALTER TABLE test_table SET (autovacuum_enabled = false);
```
- Обновляем строки 10 раз
```
postgres=# SELECT relname, n_live_tup, n_dead_tup, last_autovacuum FROM pg_stat_user_tables WHERE relname = 'test_table';
  relname   | n_live_tup | n_dead_tup |        last_autovacuum        
------------+------------+------------+-------------------------------
 test_table |    1000000 |    9997641 | 2025-04-27 12:19:29.127654+00
(1 row)

postgres=# SELECT pg_size_pretty(pg_total_relation_size('test_table'));                                                  
 pg_size_pretty 
----------------
 943 MB
(1 row)
```
Вывод: без автовакуума растет количество мертвых записей и размер таблицы прямопропорционально
