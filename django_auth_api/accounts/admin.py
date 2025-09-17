from django.contrib import admin
from django.contrib.auth.admin import UserAdmin
from .models import CustomUser, DashboardPreference


@admin.register(CustomUser)
class CustomUserAdmin(UserAdmin):
    ordering = ("email",)
    list_display = ("id", "email", "username", "is_active", "is_staff", "date_joined")
    search_fields = ("email", "username")

    fieldsets = (
        (None, {"fields": ("email", "password")}),
        ("Personal info", {"fields": ("username",)}),
        ("Permissions", {"fields": ("is_active", "is_staff", "is_superuser", "groups", "user_permissions")}),
        ("Important dates", {"fields": ("last_login", "date_joined")}),
    )

    add_fieldsets = (
        (None, {
            "classes": ("wide",),
            "fields": ("email", "password1", "password2", "is_staff", "is_superuser"),
        }),
    )

    # Make "username" optional in admin forms
    def get_form(self, request, obj=None, **kwargs):
        form = super().get_form(request, obj, **kwargs)
        if "username" in form.base_fields:
            form.base_fields["username"].required = False
        return form


@admin.register(DashboardPreference)
class DashboardPreferenceAdmin(admin.ModelAdmin):
    list_display = ("id", "user", "updated_at", "widgets_preview")
    search_fields = ("user__email",)

    def widgets_preview(self, obj):
        text = str(obj.widgets)
        return (text[:60] + "…") if len(text) > 60 else text

    widgets_preview.short_description = "widgets"
