from django.utils.dateparse import parse_datetime
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework import status

from .models import DashboardPreference, CustomUser, Event
from .serializers import (
    CustomUserSerializer,
    CustomUserCreateSerializer,
    DashboardPreferenceSerializer,
    DashboardPreferenceUpdateSerializer,
    EventSerializer,
    EventCreateUpdateSerializer,
)


# -------- Users --------
class UserProfileView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(CustomUserSerializer(request.user).data)


class UserRegisterView(APIView):
    permission_classes = [AllowAny]

    def post(self, request):
        ser = CustomUserCreateSerializer(data=request.data)
        if ser.is_valid():
            ser.save()
            return Response({"detail": "User created"}, status=status.HTTP_201_CREATED)
        return Response(ser.errors, status=status.HTTP_400_BAD_REQUEST)


# -------- Dashboard --------
class DashboardPreferenceView(APIView):
    permission_classes = [IsAuthenticated]

    def get_object(self, user: CustomUser) -> DashboardPreference:
        obj, _ = DashboardPreference.objects.get_or_create(user=user)
        return obj

    def get(self, request):
        pref = self.get_object(request.user)
        return Response(DashboardPreferenceSerializer(pref).data)

    def post(self, request):
        pref = self.get_object(request.user)
        ser = DashboardPreferenceUpdateSerializer(pref, data=request.data)
        if ser.is_valid():
            ser.save()
            return Response(DashboardPreferenceSerializer(pref).data)
        return Response(ser.errors, status=400)

    def put(self, request):
        return self.post(request)

    def patch(self, request):
        pref = self.get_object(request.user)
        ser = DashboardPreferenceUpdateSerializer(pref, data=request.data, partial=True)
        if ser.is_valid():
            ser.save()
            return Response(DashboardPreferenceSerializer(pref).data)
        return Response(ser.errors, status=400)


# -------- Events --------
class EventListCreateView(APIView):
    """
    GET /api/events/?start=ISO&end=ISO  -> list events overlapping range
    POST /api/events/                   -> create event
    """
    permission_classes = [IsAuthenticated]

    def get(self, request):
        qs = Event.objects.filter(user=request.user)

        start_s = request.query_params.get("start")
        end_s = request.query_params.get("end")
        start_dt = parse_datetime(start_s) if start_s else None
        end_dt = parse_datetime(end_s) if end_s else None

        if start_dt and end_dt:
            qs = qs.filter(start_dt__lt=end_dt, end_dt__gt=start_dt)
        elif start_dt:
            qs = qs.filter(end_dt__gt=start_dt)
        elif end_dt:
            qs = qs.filter(start_dt__lt=end_dt)

        return Response(EventSerializer(qs.order_by("start_dt"), many=True).data)

    def post(self, request):
        ser = EventCreateUpdateSerializer(data=request.data, context={"request": request})
        if ser.is_valid():
            obj = ser.save()
            return Response(EventSerializer(obj).data, status=status.HTTP_201_CREATED)
        return Response(ser.errors, status=400)


class EventDetailView(APIView):
    """
    GET/PUT/PATCH/DELETE /api/events/<id>/
    """
    permission_classes = [IsAuthenticated]

    def get_object(self, request, pk):
        return Event.objects.filter(user=request.user, pk=pk).first()

    def get(self, request, pk):
        obj = self.get_object(request, pk)
        if not obj:
            return Response({"detail": "Not found."}, status=404)
        return Response(EventSerializer(obj).data)

    def put(self, request, pk):
        obj = self.get_object(request, pk)
        if not obj:
            return Response({"detail": "Not found."}, status=404)
        ser = EventCreateUpdateSerializer(obj, data=request.data, context={"request": request})
        if ser.is_valid():
            ser.save()
            return Response(EventSerializer(obj).data)
        return Response(ser.errors, status=400)

    def patch(self, request, pk):
        obj = self.get_object(request, pk)
        if not obj:
            return Response({"detail": "Not found."}, status=404)
        ser = EventCreateUpdateSerializer(obj, data=request.data, partial=True, context={"request": request})
        if ser.is_valid():
            ser.save()
            return Response(EventSerializer(obj).data)
        return Response(ser.errors, status=400)

    def delete(self, request, pk):
        obj = self.get_object(request, pk)
        if not obj:
            return Response({"detail": "Not found."}, status=404)
        obj.delete()
        return Response(status=204)
