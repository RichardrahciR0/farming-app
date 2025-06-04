from rest_framework import viewsets
from .models import Crop
from .serializers import CropSerializer

class CropViewSet(viewsets.ModelViewSet):
    queryset = Crop.objects.all()
    serializer_class = CropSerializer
