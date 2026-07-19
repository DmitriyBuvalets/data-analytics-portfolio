import os
import json
from datetime import datetime
import time
import functions_framework
import pandas as pd
import requests

from google.cloud import bigquery
from google.oauth2 import service_account

@functions_framework.http
def update_exchange_rates():
    
    PROJECT_ID = "report"
    DATASET_ID = "analytics"
    TABLE_ID = "usd_uah_exchange_rates"
    FULL_TABLE_ID = f"{PROJECT_ID}.{DATASET_ID}.{TABLE_ID}"

    # Зчитуємо ключі з secrets
    creds_json = os.environ.get("ga_creds")
    if not creds_json:
        raise ValueError("ga_creds is not set")

    # Авторизація
    creds_dict = json.loads(creds_json)
    credentials = service_account.Credentials.from_service_account_info(creds_dict)
    client = bigquery.Client(credentials=credentials, project=credentials.project_id)

    # Отримання курсу валют
    def fetch_exchange_rates(currencies=("USD", "EUR")):
        url = "https://api.privatbank.ua/p24api/pubinfo?json&exchange&coursid=11"
        response = requests.get(url)
        data = response.json()

        today = datetime.now().date()
        results = []
        for currency in currencies:
            row = next((r for r in data if r["ccy"] == currency), None)
            if row:
                results.append({
                    "date": today,
                    "currency": row["ccy"],
                    "base_currency": row["base_ccy"],
                    "rate_type": "card_sell",
                    "sale": float(row["sale"]),
                    "buy": float(row["buy"])
                })
        return results

    # Перевірка наявності запису
    def check_if_exists(date, currency):
        query = f"""
            SELECT COUNT(*) as count
            FROM `{FULL_TABLE_ID}`
            WHERE DATE(date) = DATE('{date}')
              AND currency = '{currency}'
        """
        result = client.query(query).result()
        return next(result).count > 0

    # Вставка в BigQuery
    def insert_to_bigquery(rows):
        df = pd.DataFrame(rows)
        client.load_table_from_dataframe(df, FULL_TABLE_ID).result()

    # Основна логіка
    rows = fetch_exchange_rates(["USD", "EUR"])
    to_insert = [row for row in rows if not check_if_exists(row["date"], row["currency"])]

    if to_insert:
        insert_to_bigquery(to_insert)
        print(f"✅ Додано записи: {to_insert}", flush=True)
    else:
        print("ℹ️ Нічого не додано. Дані вже є.", flush=True)


if __name__ == "__main__":
    print("🚀 Починаю міграцію...")

    def run_job(func):
        """Обгортка для безпечного запуску кожної задачі з вимірюванням часу."""
        name = func.__name__
        print(f"\n⚙️ Запуск: {name}()")

        start_time = time.time()  # ⏱️ старт

        try:
            func()
            duration = time.time() - start_time
            print(f"✅ {name}() виконано успішно за {duration:.2f} с.")
        except Exception as e:
            duration = time.time() - start_time
            print(f"❌ Помилка у {name}() через {duration:.2f} с: {e}")


    # === Послідовний запуск усіх задач ===
    run_job(update_exchange_rates)