from django.contrib import admin
from .models import Plot, CropMedia

@admin.register(Plot)
class PlotAdmin(admin.ModelAdmin):
    list_display = ("id", "name", "type", "owner", "created_at")
    search_fields = ("name", "owner__email")
    list_filter = ("type", "growth_stage")

@admin.register(CropMedia)
class CropMediaAdmin(admin.ModelAdmin):
    list_display = ("id", "plot", "caption", "created_at")
