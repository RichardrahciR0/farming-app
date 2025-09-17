from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import CropViewSet

router = DefaultRouter()
router.register(r"crops", CropViewSet, basename="crop")

urlpatterns = [
    # Your API will be /api/crops/
    path("api/", include(router.urls)),
]
