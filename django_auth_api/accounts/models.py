from django.contrib.auth.models import AbstractUser, UserManager
from django.db import models
from django.db.models.signals import post_save
from django.dispatch import receiver
from django.conf import settings


class CustomUserManager(UserManager):
    """Authenticate with email; username is optional."""
    use_in_migrations = True

    def _create_user(self, email, password, **extra_fields):
        if not email:
            raise ValueError("The email must be set")
        email = self.normalize_email(email)
        user = self.model(email=email, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_user(self, email, password=None, **extra_fields):
        extra_fields.setdefault("is_staff", False)
        extra_fields.setdefault("is_superuser", False)
        return self._create_user(email, password, **extra_fields)

    def create_superuser(self, email, password=None, **extra_fields):
        extra_fields.setdefault("is_staff", True)
        extra_fields.setdefault("is_superuser", True)
        if extra_fields.get("is_staff") is not True:
            raise ValueError("Superuser must have is_staff=True.")
        if extra_fields.get("is_superuser") is not True:
            raise ValueError("Superuser must have is_superuser=True.")
        return self._create_user(email, password, **extra_fields)


class CustomUser(AbstractUser):
    """
    Email is the login field. Username is optional.
    """
    username = models.CharField(max_length=150, blank=True, null=True, unique=False)
    email = models.EmailField(unique=True)

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS = []

    objects = CustomUserManager()

    def __str__(self) -> str:
        return self.email


class DashboardPreference(models.Model):
    user = models.OneToOneField(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="dashboard_pref"
    )
    widgets = models.JSONField(default=list)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self) -> str:
        return f"DashboardPreference<{self.user.email}>"


@receiver(post_save, sender=CustomUser)
def create_dashboard_pref(sender, instance, created, **kwargs):
    if created:
        DashboardPreference.objects.get_or_create(user=instance, defaults={"widgets": []})


# ----------------------
# Calendar / Events
# ----------------------
class Event(models.Model):
    """
    Calendar event stored in UTC.
    """
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="events"
    )
    title = models.CharField(max_length=200)
    notes = models.TextField(blank=True)
    start_dt = models.DateTimeField()
    end_dt = models.DateTimeField()
    all_day = models.BooleanField(default=False)
    location = models.CharField(max_length=255, blank=True)

    # For Task Manager
    STATUS_CHOICES = [
        ("not_started", "Not started"),
        ("in_progress", "In Progress"),
        ("completed", "Completed"),
    ]
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default="not_started")
    completed = models.BooleanField(default=False)

    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["start_dt"]
        indexes = [
            models.Index(fields=["user", "start_dt"]),
            models.Index(fields=["user", "end_dt"]),
        ]

    def __str__(self) -> str:
        return f"Event<{self.title} @ {self.start_dt.isoformat()}>"
