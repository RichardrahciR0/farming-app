# crop_backend/crops/urls.py

from rest_framework.routers import DefaultRouter
from .views import CropViewSet

router = DefaultRouter()
# registering at the “root” of this router means
# GET /api/crops/  → CropViewSet.list()
# POST /api/crops/ → CropViewSet.create()
router.register(r"", CropViewSet, basename="crop")

# expose only the router's URLs, no include() to yourself!
urlpatterns = router.urls
