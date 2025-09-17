# django_auth_api/config/urls.py
from django.contrib import admin
from django.urls import path, include
from django.conf import settings
from django.conf.urls.static import static

from accounts.views import (
    UserProfileView,
    UserRegisterView,
    DashboardPreferenceView,
    EventListCreateView,
    EventDetailView,
)

# ✅ import your Perenual proxy view
from external_crops_perenual import external_crops_search

urlpatterns = [
    path("admin/", admin.site.urls),

    # --- Authentication ---
    path("api/auth/", include("djoser.urls")),
    path("api/auth/", include("djoser.urls.jwt")),

    # --- User profile / dashboard ---
    path("api/profile/", UserProfileView.as_view()),
    path("api/register/", UserRegisterView.as_view()),
    path("api/dashboard/", DashboardPreferenceView.as_view()),

    # --- Events ---
    path("api/events/", EventListCreateView.as_view()),
    path("api/events/<int:pk>/", EventDetailView.as_view()),

    # --- Plots + Crops (local DB) ---
    path("api/", include("plots.urls")),
    path("api/crops/", include("crops.urls")),
    path("api/", include("crop_app.urls")),

    # --- External proxy (🌱 Perenual global crops) ---
    path("api/external/crops/", external_crops_search),
]

# --- Static + media serving (dev only) ---
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
