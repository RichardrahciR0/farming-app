from django.urls import path, include
from django.contrib import admin
from accounts.views import UserProfileView, UserRegisterView

urlpatterns = [
    path('admin/', admin.site.urls),
    path('auth/', include('djoser.urls')),
    path('auth/', include('djoser.urls.jwt')),
    path('profile/', UserProfileView.as_view()),
    path('register/', UserRegisterView.as_view()),
]
