from django.contrib import admin
from .models import Crop

@admin.register(Crop)
class CropAdmin(admin.ModelAdmin):
    # remove created_at here
    list_display = ("id", "name", "spacing", "harvest_time")
    search_fields = ("name",)
    list_filter = ("harvest_time",)
    ordering = ("name",)
