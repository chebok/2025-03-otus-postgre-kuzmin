## Шаг 1: Описание тестового стенда и характера нагрузки
Тестирование проводится на виртуальной машине в Яндекс Облаке со следующими параметрами:
- Платформа: Intel Ice Lake
- vCPU: 2 ядра (20% гарантированной доли)
- RAM: 1 ГБ
- Диск: отдельный том 10 ГБ, примонтирован в `/mnt/pgdata`
- ОС: Ubuntu 22.04 LTS

Из-за ограниченных ресурсов (1 ГБ RAM, частичная загрузка CPU) результаты тестирования могут быть подвержены небольшим колебаниям производительности. Тем не менее, стенд позволяет корректно оценить базовую производительность PostgreSQL 16 в условиях ограниченного объёма памяти и ресурсов процессора.


Ожидаемый профиль нагрузки приложения "Book Library":
- Около 80% операций составляют чтения (`SELECT`).
- Около 20% операций составляют записи (`INSERT`, `UPDATE`).

## Шаг 2: Тест на дефолтной конфигурации
- Зафиксировать исходную производительность PostgreSQL 16 в дефолтной конфигурации без тюнинга. 
- Базовый тест проводится с помощью стандартной рабочей нагрузки pgbench.

Обоснование выбора параметров:
- `-c 50` — ограниченное количество подключений, чтобы не перегружать виртуальную машину с 1 ГБ RAM.
- `-j 2` — соответствует количеству доступных vCPU для оптимального распределения нагрузки.
- `-T 60` — достаточное время для усреднения результатов без риска перегрева виртуальных ресурсов.

Тестовый сценарий операций сохранён в отдельном файле:
- [custom-workload.sql](./custom-workload.sql)

Файл содержит скрипт, моделирующий нагрузку: 80% чтение и 20% запись.

Инициализация тестовой базы и запуск теста:
```bash
sudo -i -u postgres
pgbench -i -U postgres postgres
pgbench -f /home/kuzmin/benchmarks/custom-workload.sql -c 50 -j 2 -T 60 postgres
```
- Количество клиентов: 50
- Количество потоков: 2
- Длительность теста: 60 секунд
- Общее количество выполненных транзакций: 13965
- Количество ошибок: 0 (0.000%)
- Средняя latency транзакции: 215.267 ms
- Пропускная способность (TPS): 232.269496 транзакций/секунду (без учета времени подключения)

Вывод: на дефолтной конфигурации PostgreSQL 16 виртуальная машина с 2 vCPU и 1 ГБ RAM обеспечивает пропускную способность около 232 TPS при средней задержке ~215 мс.

## Шаг 3: Тюнинг под максимальную производительность


- Создаём бэкап оригинального конфига
```bash
sudo cp /etc/postgresql/16/main/postgresql.conf /etc/postgresql/16/main/postgresql.conf.bak
```
- Проведена оптимизация настроек PostgreSQL через сервис **Cybertec PostgreSQL Configurator** ([ссылка](https://www.cybertec-postgresql.com/en/postgresql-tuning-wizard/)).

  Параметры генерации:
    - RAM: 1 ГБ
    - CPU: 2 vCPU
    - Диск: SSD
    - Тип нагрузки: Mostly simple SQL with occasional complicated SQL
    - Ожидаемое количество одновременных подключений: 50

- Сгенерированный конфигурационный файл сохранён:
  - [postgresql.conf](./postgresql.conf)
- Редактируем конфиг и перезапускаем кластер

## Шаг 4: Результат

- Снова запускаем наш тестовый сценарий
```bash
pgbench -f /home/kuzmin/benchmarks/custom-workload.sql -c 50 -j 2 -T 60 postgres
```

Результат после тюнинга:

- Количество клиентов: 50
- Количество потоков: 2
- Длительность теста: 60 секунд
- Общее количество выполненных транзакций: 14398
- Количество ошибок: 0 (0.000%)
- Средняя latency транзакции: 208.464 ms
- Пропускная способность (TPS): 239.849308 транзакций/секунду (без учета времени подключения)

Вывод:
- После применения оптимизированного конфига результат теста показал небольшое улучшение TPS (transactions per second) и latency.
- Однако эффект оказался ограниченным ввиду слабых ресурсов виртуальной машины (2 CPU, 1 ГБ RAM).
- Основной bottleneck на данном этапе — нехватка вычислительных ресурсов сервера.
