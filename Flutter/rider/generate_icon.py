from PIL import Image, ImageDraw, ImageFont
import os

img_size = 1024
image = Image.new('RGB', (img_size, img_size), color='white')
draw = ImageDraw.Draw(image)

text = "Gaman"
# Try to find a nice font, or fallback to default
try:
    # Use a common macOS font
    font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 160)
except IOError:
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 160)
    except IOError:
        font = ImageFont.load_default()

# Get text bounding box
bbox = draw.textbbox((0, 0), text, font=font)
text_w = bbox[2] - bbox[0]
text_h = bbox[3] - bbox[1]

x = (img_size - text_w) / 2
y = (img_size - text_h) / 2 - bbox[1] # adjusting for ascent

draw.text((x, y), text, fill='black', font=font)

os.makedirs("assets/images/logo", exist_ok=True)
image.save("assets/images/logo/gaman_app_icon.png")
print("Image generated successfully.")
