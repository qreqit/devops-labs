"""
Unit tests for Lab 3 Lambda function (S3 to PostgreSQL with deduplication).
"""

import io
import unittest
from unittest.mock import MagicMock, patch

import lambda_function


class TestLab3LambdaFunction(unittest.TestCase):

    def setUp(self):
        self.mock_s3 = MagicMock()
        lambda_function.s3_client = self.mock_s3

    def test_detect_target_table_by_header(self):
        # Виявлення за колонками в заголовку CSV
        table_org = lambda_function.detect_target_table("edrpou,legal_name,city", "data_file.csv")
        self.assertEqual(table_org, "organizations")

        table_tender = lambda_function.detect_target_table("tender_id,title,expected_value", "data_file.csv")
        self.assertEqual(table_tender, "tenders")

    def test_detect_target_table_by_filename(self):
        # Виявлення за назвою файлу
        self.assertEqual(lambda_function.detect_target_table("col1,col2", "organizations_2026.csv"), "organizations")
        self.assertEqual(lambda_function.detect_target_table("col1,col2", "tenders_q4.csv"), "tenders")

    def test_detect_target_table_unknown(self):
        with self.assertRaises(ValueError):
            lambda_function.detect_target_table("col1,col2", "unknown.csv")

    @patch("lambda_function.get_db_connection")
    @patch("lambda_function.datetime")
    def test_process_s3_file_organizations_with_stored_proc(self, mock_datetime, mock_get_conn):
        # Фіксований час для передбачуваного імені файлу
        fixed_time = MagicMock()
        fixed_time.strftime.return_value = "20261114_150000"
        mock_datetime.now.return_value = fixed_time

        # Мокаємо S3 Body
        csv_data = (
            "edrpou,legal_name,short_name,org_type,region,city,postal_code,address,email,phone\n"
            "02125266,ПНУ,ПНУ,ЗВО,Івано-Франківська область,м. Івано-Франківськ,76018,вул. Шевченка,mail@pnu.ua,123\n"
            "02125266,ПНУ Нова назва,ПНУ,ЗВО,Івано-Франківська область,м. Івано-Франківськ,76018,вул. Шевченка,mail@pnu.ua,123\n"
        )
        mock_body = MagicMock()
        mock_body.read.return_value = csv_data.encode("utf-8")
        self.mock_s3.get_object.return_value = {"Body": mock_body}

        # Мокаємо з'єднання з БД
        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_conn.cursor.return_value.__enter__.return_value = mock_cursor
        mock_cursor.fetchone.return_value = [2] # 2 рядки у staging
        mock_get_conn.return_value = (mock_conn, "psycopg2")

        # Вмикаємо режим виклику збережуваної процедури
        lambda_function.USE_STORED_PROCEDURE = True

        event = {
            "Records": [
                {
                    "s3": {
                        "bucket": {"name": "test-bucket"},
                        "object": {"key": "input/organizations.csv"}
                    }
                }
            ]
        }

        res = lambda_function.lambda_handler(event, None)
        self.assertEqual(res["statusCode"], 200)

        # Перевіряємо створення тимчасової таблиці
        mock_cursor.execute.assert_any_call("CREATE TEMP TABLE temp_organizations (LIKE organizations INCLUDING DEFAULTS) ON COMMIT DROP;")

        # Перевіряємо виклик команди COPY через copy_expert
        self.assertTrue(mock_cursor.copy_expert.called)

        # Перевіряємо виклик збережуваної процедури дедуплікації
        mock_cursor.execute.assert_any_call("CALL sync_organizations_from_staging(%s);", (lambda_function.DEDUP_MODE,))

        # Перевіряємо фіксацію транзакції
        mock_conn.commit.assert_called_once()

        # Перевіряємо переміщення файлу в S3
        self.mock_s3.copy_object.assert_called_once_with(
            Bucket="test-bucket",
            CopySource={"Bucket": "test-bucket", "Key": "input/organizations.csv"},
            Key="processed/organizations_20261114_150000.csv"
        )
        self.mock_s3.delete_object.assert_called_once_with(
            Bucket="test-bucket",
            Key="input/organizations.csv"
        )

    @patch("lambda_function.get_db_connection")
    @patch("lambda_function.datetime")
    def test_process_s3_file_with_direct_upsert(self, mock_datetime, mock_get_conn):
        fixed_time = MagicMock()
        fixed_time.strftime.return_value = "20261114_150000"
        mock_datetime.now.return_value = fixed_time

        csv_data = (
            "tender_id,title,description,procuring_entity_edrpou,expected_value,currency,procedure_type,status,start_date,end_date\n"
            "UA-01,Закупівля 1,Опис,02125266,1000.0,UAH,Торги,active,2026-01-01,2026-02-01\n"
        )
        mock_body = MagicMock()
        mock_body.read.return_value = csv_data.encode("utf-8")
        self.mock_s3.get_object.return_value = {"Body": mock_body}

        mock_conn = MagicMock()
        mock_cursor = MagicMock()
        mock_conn.cursor.return_value.__enter__.return_value = mock_cursor
        mock_cursor.fetchone.side_effect = [
            [1],     # SELECT COUNT(*) FROM temp_tenders
            [1, 0]   # SELECT COUNT(*) FILTER ... FROM upsert_res (1 insert, 0 update)
        ]
        mock_get_conn.return_value = (mock_conn, "psycopg2")

        # Вимикаємо збережувану процедуру для тестування прямого UPSERT
        lambda_function.USE_STORED_PROCEDURE = False

        event = {
            "Records": [
                {
                    "s3": {
                        "bucket": {"name": "test-bucket"},
                        "object": {"key": "input/tenders.csv"}
                    }
                }
            ]
        }

        res = lambda_function.lambda_handler(event, None)
        self.assertEqual(res["statusCode"], 200)

        # Перевіряємо створення тимчасової таблиці temp_tenders
        mock_cursor.execute.assert_any_call("CREATE TEMP TABLE temp_tenders (LIKE tenders INCLUDING DEFAULTS) ON COMMIT DROP;")
        mock_conn.commit.assert_called_once()


if __name__ == "__main__":
    unittest.main()

