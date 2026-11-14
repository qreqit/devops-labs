"""
Unit tests for AWS Lambda S3 router function.
"""

import unittest
from unittest.mock import MagicMock, patch
import re

import lambda_function


class TestLambdaFunction(unittest.TestCase):

    def setUp(self):
        # Надаємо мок для s3_client
        self.mock_s3 = MagicMock()
        lambda_function.s3_client = self.mock_s3

    def test_csv_matching(self):
        self.assertTrue(lambda_function.is_file_matching_pattern("data_2024.csv"))
        self.assertTrue(lambda_function.is_file_matching_pattern("data_0000.csv"))
        self.assertTrue(lambda_function.is_file_matching_pattern("data_9999.csv"))

    def test_csv_not_matching(self):
        self.assertFalse(lambda_function.is_file_matching_pattern("data_202411.csv"))
        self.assertFalse(lambda_function.is_file_matching_pattern("data_abc.csv"))
        self.assertFalse(lambda_function.is_file_matching_pattern("other_2024.csv"))
        self.assertFalse(lambda_function.is_file_matching_pattern("data_2024.csv.bak"))

    def test_json_matching(self):
        self.assertTrue(lambda_function.is_file_matching_pattern("report_2024.json"))
        self.assertTrue(lambda_function.is_file_matching_pattern("report_0123.json"))

    def test_json_not_matching(self):
        self.assertFalse(lambda_function.is_file_matching_pattern("report_202401.json"))
        self.assertFalse(lambda_function.is_file_matching_pattern("report_annual.json"))
        self.assertFalse(lambda_function.is_file_matching_pattern("data_2024.json"))

    def test_unsupported_extensions(self):
        self.assertFalse(lambda_function.is_file_matching_pattern("data_2024.txt"))
        self.assertFalse(lambda_function.is_file_matching_pattern("data_2024.pdf"))

    @patch("lambda_function.datetime")
    def test_process_valid_csv(self, mock_datetime):
        # Фіксуємо дату і час
        fixed_now = MagicMock()
        fixed_now.strftime.return_value = "20261114_143000"
        mock_datetime.now.return_value = fixed_now

        event = {
            "Records": [
                {
                    "s3": {
                        "bucket": {"name": "my-test-bucket"},
                        "object": {"key": "input/data_2024.csv"}
                    }
                }
            ]
        }

        res = lambda_function.lambda_handler(event, None)
        self.assertEqual(res["statusCode"], 200)

        # Перевіряємо копіювання до processed/ із таймстампом
        self.mock_s3.copy_object.assert_called_once_with(
            Bucket="my-test-bucket",
            CopySource={"Bucket": "my-test-bucket", "Key": "input/data_2024.csv"},
            Key="processed/data_2024_20261114_143000.csv"
        )
        # Перевіряємо видалення оригіналу
        self.mock_s3.delete_object.assert_called_once_with(
            Bucket="my-test-bucket",
            Key="input/data_2024.csv"
        )

    @patch("lambda_function.datetime")
    def test_process_valid_json(self, mock_datetime):
        fixed_now = MagicMock()
        fixed_now.strftime.return_value = "20261114_150000"
        mock_datetime.now.return_value = fixed_now

        event = {
            "Records": [
                {
                    "s3": {
                        "bucket": {"name": "my-test-bucket"},
                        "object": {"key": "input/report_5678.json"}
                    }
                }
            ]
        }

        res = lambda_function.lambda_handler(event, None)
        self.assertEqual(res["statusCode"], 200)

        self.mock_s3.copy_object.assert_called_once_with(
            Bucket="my-test-bucket",
            CopySource={"Bucket": "my-test-bucket", "Key": "input/report_5678.json"},
            Key="processed/report_5678_20261114_150000.json"
        )
        self.mock_s3.delete_object.assert_called_once_with(
            Bucket="my-test-bucket",
            Key="input/report_5678.json"
        )

    def test_process_invalid_csv_to_ignored(self):
        event = {
            "Records": [
                {
                    "s3": {
                        "bucket": {"name": "my-test-bucket"},
                        "object": {"key": "input/bad_name.csv"}
                    }
                }
            ]
        }

        res = lambda_function.lambda_handler(event, None)
        self.assertEqual(res["statusCode"], 200)

        # Має бути переміщено в ignored/ без зміни назви
        self.mock_s3.copy_object.assert_called_once_with(
            Bucket="my-test-bucket",
            CopySource={"Bucket": "my-test-bucket", "Key": "input/bad_name.csv"},
            Key="ignored/bad_name.csv"
        )
        self.mock_s3.delete_object.assert_called_once_with(
            Bucket="my-test-bucket",
            Key="input/bad_name.csv"
        )

    def test_process_invalid_json_to_ignored(self):
        event = {
            "Records": [
                {
                    "s3": {
                        "bucket": {"name": "my-test-bucket"},
                        "object": {"key": "input/random_data.json"}
                    }
                }
            ]
        }

        res = lambda_function.lambda_handler(event, None)
        self.assertEqual(res["statusCode"], 200)

        self.mock_s3.copy_object.assert_called_once_with(
            Bucket="my-test-bucket",
            CopySource={"Bucket": "my-test-bucket", "Key": "input/random_data.json"},
            Key="ignored/random_data.json"
        )
        self.mock_s3.delete_object.assert_called_once_with(
            Bucket="my-test-bucket",
            Key="input/random_data.json"
        )

    def test_ignore_outside_input_folder(self):
        # Захист від нескінченного циклу обробки (файли вже в processed або ignored)
        event = {
            "Records": [
                {
                    "s3": {
                        "bucket": {"name": "my-test-bucket"},
                        "object": {"key": "processed/data_2024_20261114_143000.csv"}
                    }
                },
                {
                    "s3": {
                        "bucket": {"name": "my-test-bucket"},
                        "object": {"key": "ignored/bad_name.csv"}
                    }
                }
            ]
        }

        res = lambda_function.lambda_handler(event, None)
        self.assertEqual(res["statusCode"], 200)
        self.mock_s3.copy_object.assert_not_called()
        self.mock_s3.delete_object.assert_not_called()

    def test_ignore_folder_creation(self):
        event = {
            "Records": [
                {
                    "s3": {
                        "bucket": {"name": "my-test-bucket"},
                        "object": {"key": "input/"}
                    }
                }
            ]
        }

        res = lambda_function.lambda_handler(event, None)
        self.assertEqual(res["statusCode"], 200)
        self.mock_s3.copy_object.assert_not_called()
        self.mock_s3.delete_object.assert_not_called()

    @patch("lambda_function.datetime")
    def test_url_encoded_filename(self, mock_datetime):
        fixed_now = MagicMock()
        fixed_now.strftime.return_value = "20261114_143000"
        mock_datetime.now.return_value = fixed_now

        # S3 надсилає спецсимволи та пробіли закодованими
        event = {
            "Records": [
                {
                    "s3": {
                        "bucket": {"name": "my-test-bucket"},
                        "object": {"key": "input/invalid+space%20file.csv"}
                    }
                }
            ]
        }

        res = lambda_function.lambda_handler(event, None)
        self.assertEqual(res["statusCode"], 200)

        self.mock_s3.copy_object.assert_called_once_with(
            Bucket="my-test-bucket",
            CopySource={"Bucket": "my-test-bucket", "Key": "input/invalid space file.csv"},
            Key="ignored/invalid space file.csv"
        )


if __name__ == "__main__":
    unittest.main()

