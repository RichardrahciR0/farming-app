from rest_framework import generics, permissions
from .models import CustomUser
from .serializers import CustomUserSerializer, CustomUserCreateSerializer

class UserProfileView(generics.RetrieveAPIView):
    serializer_class = CustomUserSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_object(self):
        return self.request.user

class UserRegisterView(generics.CreateAPIView):
    queryset = CustomUser.objects.all()
    serializer_class = CustomUserCreateSerializer
    permission_classes = [permissions.AllowAny]
