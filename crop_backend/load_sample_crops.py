from crops.models import Crop

def run():
    Crop.objects.create(
        name='Tomato',
        spacing='45 cm',
        harvest_time='60–85 days',
        plant_type='Vegetable',
        soil_type='Loamy',
        sunlight_needs='Full Sun',
        watering_needs='Moderate',
        growth_stages='Seedling, Vegetative, Flowering, Fruiting',
        fertiliser_tips='Use balanced NPK fertiliser every 2 weeks',
        pest_notes='Watch for aphids and whiteflies',
        image='tomato.png'
    )
    Crop.objects.create(
        name='Mint',
        spacing='30 cm',
        harvest_time='90 days',
        plant_type='Herb',
        soil_type='Sandy Loam',
        sunlight_needs='Partial Sun',
        watering_needs='Frequent',
        growth_stages='Sprouting, Spreading, Mature',
        fertiliser_tips='Organic compost monthly',
        pest_notes='Susceptible to rust and leaf spot',
        image='mint.png'
    )
    Crop.objects.create(
        name='Wheat',
        spacing='15 cm',
        harvest_time='120 days',
        plant_type='Grain',
        soil_type='Clay Loam',
        sunlight_needs='Full Sun',
        watering_needs='Moderate',
        growth_stages='Germination, Tillering, Heading, Ripening',
        fertiliser_tips='Apply nitrogen-rich fertiliser during tillering',
        pest_notes='Monitor for rust and aphids',
        image='wheat.jpeg'
    )
    Crop.objects.create(
        name='Coriander',
        spacing='20 cm',
        harvest_time='45 days',
        plant_type='Herb',
        soil_type='Sandy',
        sunlight_needs='Full Sun',
        watering_needs='Low to Moderate',
        growth_stages='Seedling, Leafing, Flowering',
        fertiliser_tips='Use compost at planting time',
        pest_notes='Avoid overwatering to prevent damping-off',
        image='coriander.png'
    )
    Crop.objects.create(
        name='Asparagus',
        spacing='40 cm',
        harvest_time='2–3 years',
        plant_type='Vegetable',
        soil_type='Well-drained Loam',
        sunlight_needs='Full Sun',
        watering_needs='Regular',
        growth_stages='Dormant, Spear emergence, Fern stage',
        fertiliser_tips='High phosphorus in early growth',
        pest_notes='Watch for asparagus beetles',
        image='asparagus.png'
    )
    Crop.objects.create(
        name='Corn',
        spacing='25 cm',
        harvest_time='60–100 days',
        plant_type='Grain',
        soil_type='Fertile Loam',
        sunlight_needs='Full Sun',
        watering_needs='High',
        growth_stages='Germination, Tasseling, Silking, Maturity',
        fertiliser_tips='Side-dress with nitrogen at knee-high stage',
        pest_notes='Beware of corn borers and aphids',
        image='corn.png'
    )
    Crop.objects.create(
        name='Kale',
        spacing='45 cm',
        harvest_time='55–75 days',
        plant_type='Vegetable',
        soil_type='Rich Loam',
        sunlight_needs='Full to Partial Sun',
        watering_needs='Moderate',
        growth_stages='Seedling, Leaf development, Harvest',
        fertiliser_tips='Use nitrogen-rich compost monthly',
        pest_notes='Cabbage worms and flea beetles are common',
        image='kale.png'
    )
    Crop.objects.create(
        name='Dill',
        spacing='25 cm',
        harvest_time='60 days',
        plant_type='Herb',
        soil_type='Sandy Loam',
        sunlight_needs='Full Sun',
        watering_needs='Low',
        growth_stages='Sprouting, Leafing, Flowering, Seeding',
        fertiliser_tips='Avoid excess nitrogen',
        pest_notes='Aphids and caterpillars may be present',
        image='dill.png'
    )
    Crop.objects.create(
        name='Parsley',
        spacing='20 cm',
        harvest_time='70–90 days',
        plant_type='Herb',
        soil_type='Moist Loam',
        sunlight_needs='Partial Shade',
        watering_needs='Consistent',
        growth_stages='Germination, Leafing, Full Growth',
        fertiliser_tips='Balanced fertiliser monthly',
        pest_notes='Keep soil well-drained to avoid root rot',
        image='parsley.png'
    )
    Crop.objects.create(
        name='Chives',
        spacing='20 cm',
        harvest_time='60 days',
        plant_type='Herb',
        soil_type='Well-drained Loam',
        sunlight_needs='Full Sun',
        watering_needs='Regular',
        growth_stages='Sprouting, Leafing, Harvest',
        fertiliser_tips='Light compost monthly',
        pest_notes='Thrips and leaf miners may occur',
        image='chives.png'
    )
