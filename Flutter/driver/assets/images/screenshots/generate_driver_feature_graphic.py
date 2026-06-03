import os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

# Config
DIR = '/Users/rameez/Desktop/MANA YATRA/Flutter/driver/assets/images/screenshots'
WIDTH, HEIGHT = 1024, 500

def create_gradient():
    base = Image.new('RGB', (WIDTH, HEIGHT), "#111111")
    top = Image.new('RGB', (WIDTH, HEIGHT), "#2a2a2a")
    mask = Image.new('L', (WIDTH, HEIGHT))
    mask_data = []
    for y in range(HEIGHT):
        mask_data.extend([int(255 * (x / WIDTH)) for x in range(WIDTH)])
    mask.putdata(mask_data)
    base.paste(top, (0, 0), mask)
    return base

def mask_rounded(img, radius):
    mask = Image.new('L', img.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, img.width, img.height), radius=radius, fill=255)
    
    result = img.copy()
    if result.mode != 'RGBA':
        result = result.convert('RGBA')
    result.putalpha(mask)
    return result

def add_glow(bg, paste_img, x, y, glow_color, radius):
    # Create a blurred version of the mask to act as a glow
    glow = Image.new('RGBA', bg.size, (0,0,0,0))
    # We paste a solid color of the shape, then blur
    shape = Image.new('RGBA', paste_img.size, glow_color)
    # Apply alpha from paste_img
    shape.putalpha(paste_img.split()[3])
    glow.paste(shape, (x, y), shape)
    glow = glow.filter(ImageFilter.GaussianBlur(radius=radius))
    bg.paste(glow, (0, 0), glow)
    return bg

bg = create_gradient()

# 1. Process Driver AI Image (Right side)
driver_img_path = os.path.join(DIR, 'driver.png')
if os.path.exists(driver_img_path):
    driver_img = Image.open(driver_img_path).convert("RGBA")
    # It's a 9:16 image. Resize height to 440
    d_h = 440
    ratio = d_h / driver_img.height
    d_w = int(driver_img.width * ratio)
    driver_img = driver_img.resize((d_w, d_h), Image.Resampling.LANCZOS)
    
    # Round corners to blend beautifully
    driver_img = mask_rounded(driver_img, 30)
    
    # Place on right side
    dx = WIDTH - d_w - 50
    dy = 30
    
    # Add a soft golden/yellow glow behind it to mix with background
    bg = add_glow(bg, driver_img, dx, dy, "#FFCC00", radius=40)
    bg.paste(driver_img, (dx, dy), driver_img)

# 2. Process App Logo (Left side)
logo_path = os.path.join(DIR, 'app_logo.png')
if os.path.exists(logo_path):
    logo = Image.open(logo_path).convert("RGBA")
    logo = logo.resize((180, 180), Image.Resampling.LANCZOS)
    
    # The user asked to blend or cutout the square logo
    # We will make it a perfect circle
    mask = Image.new('L', logo.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((0, 0, logo.width, logo.height), fill=255)
    logo.putalpha(mask)
    
    lx = 80
    ly = 80
    # Add a subtle white/glow behind the logo
    bg = add_glow(bg, logo, lx, ly, "#FFFFFF", radius=25)
    bg.paste(logo, (lx, ly), logo)

# 3. Add Caption
try:
    font_large = ImageFont.truetype("/System/Library/Fonts/Supplemental/Impact.ttf", 60)
except:
    font_large = ImageFont.load_default()

text = "DRIVE ON YOUR TERMS."
draw = ImageDraw.Draw(bg)

bbox = draw.textbbox((0, 0), text, font=font_large)
tw = bbox[2] - bbox[0]
th = bbox[3] - bbox[1]

tx = 80
ty = 330

padding_x = 35
padding_y = 20
rect_coords = [
    tx - padding_x, 
    ty - padding_y, 
    tx + tw + padding_x, 
    ty + th + padding_y + 10
]

# Yellow rounded rectangle
draw.rounded_rectangle(rect_coords, radius=20, fill="#FFCC00")
# Black text, NO shadow
draw.text((tx, ty), text, font=font_large, fill="#000000")

# Save
out_path = os.path.join(DIR, 'feature_graphic.png')
bg.convert('RGB').save(out_path, format="PNG")
print(f"Generated {out_path}")
