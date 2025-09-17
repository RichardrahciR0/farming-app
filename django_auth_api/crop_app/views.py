from rest_framework import viewsets, parsers
from .models import Crop
from .serializers import CropSerializer

class CropViewSet(viewsets.ModelViewSet):
    queryset = Crop.objects.all().order_by("name")
    serializer_class = CropSerializer
    # Accepts JSON (no image) and multipart/form-data (with image)
    parser_classes = [parsers.JSONParser, parsers.FormParser, parsers.MultiPartParser]
