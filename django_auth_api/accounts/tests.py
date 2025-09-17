from django.test import TestCase
from django.urls import reverse
from rest_framework.test import APIClient
from rest_framework import status
from .models import CustomUser


class AccountsFlowTests(TestCase):
    def setUp(self):
        self.client = APIClient()

    def test_signup_login(self):
        # Signup
        r = self.client.post("/api/auth/users/", {
            "email": "test@example.com",
            "password": "pass1234",
            "re_password": "pass1234",
        }, format="json")
        self.assertEqual(r.status_code, status.HTTP_201_CREATED)

        # Login (email + password)
        r = self.client.post("/api/auth/jwt/create/", {
            "email": "test@example.com",
            "password": "pass1234",
        }, format="json")
        self.assertEqual(r.status_code, status.HTTP_200_OK)
        self.assertIn("access", r.data)
