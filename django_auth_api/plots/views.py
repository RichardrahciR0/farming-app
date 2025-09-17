from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from django.shortcuts import get_object_or_404

from .models import Plot, CropMedia
from .serializers import PlotSerializer, CropMediaSerializer
from .permissions import IsOwnerOrReadOnly


class PlotViewSet(viewsets.ModelViewSet):
    serializer_class = PlotSerializer
    permission_classes = [IsAuthenticated, IsOwnerOrReadOnly]

    def get_queryset(self):
        qs = Plot.objects.all().select_related("owner").prefetch_related("images")
        mine = self.request.query_params.get("mine")
        if mine in ("1", "true", "True", "yes"):
            qs = qs.filter(owner=self.request.user)
        return qs

    def perform_create(self, serializer):
        serializer.save(owner=self.request.user)

    # POST /api/plots/{id}/media/
    @action(detail=True, methods=["post"], url_path="media")
    def upload_media(self, request, pk=None):
        plot = self.get_object()
        if plot.owner_id != request.user.id:
            return Response({"detail": "Not allowed."}, status=status.HTTP_403_FORBIDDEN)

        file = request.FILES.get("image")
        caption = request.data.get("caption", "")

        if not file:
            return Response({"detail": "image is required (multipart)."}, status=status.HTTP_400_BAD_REQUEST)

        media = CropMedia.objects.create(plot=plot, image=file, caption=caption)
        serializer = CropMediaSerializer(media, context={"request": request})
        return Response(serializer.data, status=status.HTTP_201_CREATED)
