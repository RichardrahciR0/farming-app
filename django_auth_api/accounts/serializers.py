from djoser.serializers import UserCreateSerializer as DjoserUserCreateSerializer
from rest_framework import serializers

from .models import CustomUser, DashboardPreference, Event


# -----------------
# Users
# -----------------
class CustomUserCreateSerializer(DjoserUserCreateSerializer):
    class Meta:
        model = CustomUser
        fields = ("id", "email", "password", "re_password")
        extra_kwargs = {"password": {"write_only": True}, "re_password": {"write_only": True}}


class CustomUserSerializer(serializers.ModelSerializer):
    class Meta:
        model = CustomUser
        fields = ("id", "email", "username")


# -----------------
# Dashboard
# -----------------
class DashboardPreferenceSerializer(serializers.ModelSerializer):
    widgets = serializers.JSONField()

    class Meta:
        model = DashboardPreference
        fields = ("widgets", "updated_at")


class DashboardPreferenceUpdateSerializer(serializers.ModelSerializer):
    widgets = serializers.JSONField()

    class Meta:
        model = DashboardPreference
        fields = ("widgets",)

    def validate_widgets(self, value):
        if not isinstance(value, list):
            raise serializers.ValidationError("widgets must be a list")
        for i, item in enumerate(value):
            if not isinstance(item, dict):
                raise serializers.ValidationError(f"widgets[{i}] must be an object")
            if "name" not in item or "visible" not in item:
                raise serializers.ValidationError(
                    f"widgets[{i}] must include 'name' and 'visible'"
                )
            if not isinstance(item["name"], str):
                raise serializers.ValidationError(f"widgets[{i}].name must be a string")
            if not isinstance(item["visible"], bool):
                raise serializers.ValidationError(f"widgets[{i}].visible must be a boolean")
        return value


# -----------------
# Events
# -----------------
class EventSerializer(serializers.ModelSerializer):
    class Meta:
        model = Event
        fields = (
            "id",
            "title",
            "notes",
            "start_dt",
            "end_dt",
            "all_day",
            "location",
            "status",
            "completed",
            "updated_at",
        )


class EventCreateUpdateSerializer(serializers.ModelSerializer):
    class Meta:
        model = Event
        fields = (
            "title",
            "notes",
            "start_dt",
            "end_dt",
            "all_day",
            "location",
            "status",
            "completed",
        )

    def validate(self, attrs):
        start = attrs.get("start_dt") or getattr(self.instance, "start_dt", None)
        end = attrs.get("end_dt") or getattr(self.instance, "end_dt", None)
        if start and end and end < start:
            raise serializers.ValidationError("end_dt must be after start_dt.")
        return attrs

    def create(self, validated_data):
        return Event.objects.create(user=self.context["request"].user, **validated_data)
