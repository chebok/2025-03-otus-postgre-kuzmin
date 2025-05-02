## Шаг 0: Подготовка тестового стенда
Тестирование проводится на виртуальной машине в Яндекс Облаке со следующими параметрами:
- Платформа: Intel Ice Lake
- vCPU: 2 ядра
- RAM: 4 ГБ
- Диск: ssd 10 ГБ,
- ОС: Ubuntu 22.04 LTS
- Postgres 16-й

## Шаг 1: Оцениваем журнальные файлы

Инициализация тестовой базы и запуск теста 10 минут:
```bash
sudo -i -u postgres
pgbench -i -U postgres postgres
pgbench -U postgres -T 600 -c 10 -j 4 postgres
```
Результат
- Всего 4 WAL-файла (~65 МБ)
- Нагрузка 10 минут, чекпоинты каждые 30 секунд (~20 чекпоинтов)
- Средний объём WAL на чекпоинт ≈ 3.25 МБ

Время выполнения чекпоинтов почти совпадает с их интервалом 26–27 секунд.
Все чекпоинты были по таймеру, и 1 внеплановый чекпоинт был вызван при остановке сервера. Это штатное поведение PostgreSQL: при остановке он должен гарантировать целостность данных и форсировать последний чекпоинт. В остальном все чекпоинты шли строго каждые 30 секунд, как и было настроено.

## Шаг 2: Тест на tps в sync/аsync режимах

Запускаем сначала на synchronous_commit = on
```bash
sudo -i -u postgres
pgbench -U postgres -T 60 -c 10 -j 4 postgres
```

Результат
- Пропускная способность (TPS): 313.093422 транзакций/секунду

Второй раз на synchronous_commit = off
Меняем конфиг и перезапускаем кластер
```bash
sudo -i -u postgres
pgbench -U postgres -T 60 -c 10 -j 4 postgres
```

Результат
- Пропускная способность (TPS): 3103.650146 транзакций/секунду

Вывод: видим 10-кратное увеличение производительности, так как мы теперь не дожидаемся записи на диск.

## Шаг 3: Контрольные суммы страниц

- Создаём кластер с контрольными суммами
```bash
sudo -u postgres pg_createcluster 16 main -- --data-checksums
```

```sql
CREATE TABLE test_table (
  id SERIAL PRIMARY KEY,
  data TEXT
);
INSERT INTO test_table (data) VALUES ('row 1'), ('row 2'), ('row 3');
```

- Получаем путь к файлу таблицы
```sql
SELECT pg_relation_filepath('test_table');
```
Результат: base/5/16389

- Вносим изменения в файл
```bash
sudo -u postgres xxd -r - /var/lib/postgresql/16/main/base/5/16389 <<EOF
00000000: FF00 0000
EOF
```

- Делаем выборку
```sql
SELECT * FROM test_table;
```
```
WARNING:  page verification failed, calculated checksum 13610 but expected 11530
ERROR:  invalid page in block 0 of relation base/5/16389
```

Далее дописываем в конфиг zero_damaged_pages = on чтобы продолжить работу

```
kuzmin@pg-2:~$ sudo -u postgres psql -c "SELECT * FROM test_table;"
WARNING:  page verification failed, calculated checksum 13610 but expected 11530
WARNING:  invalid page in block 0 of relation base/5/16389; zeroing out page
 id | data 
----+------
(0 rows)
```
Результат: pg заменил битую страницу на пустую
