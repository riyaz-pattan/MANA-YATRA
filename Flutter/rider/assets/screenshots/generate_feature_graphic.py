from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os
import math

W, H = 1024, 500

def create_gradient():
    base = Image.new('RGB', (1, H))
    # Vibrant mobility gradient: Cyan to Deep Blue
    top = (0, 198, 255)
    bottom = (0, 114, 255)
    for y in range(H):
        r = int(top[0] + (bottom[0] - top[0]) * y / H)
        g = int(top[1] + (bottom[1] - top[1]) * y / H)
        b = int(top[2] + (bottom[2] - top[2]) * y / H)
        base.putpixel((0, y), (r, g, b))
    return base.resize((W, H))

# Load a bold font
font = None
font_size = 65
font_paths = [
    "/System/Library/Fonts/Supplemental/Impact.ttf",
    "/System/Library/Fonts/Avenir Next.ttc",
    "/Library/Fonts/Arial Bold.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
]
for path in font_paths:
    try:
        index = 0
        if "Avenir Next" in path: index = 1
        if "Helvetica" in path: index = 1
        font = ImageFont.truetype(path, font_size, index=index)
        break
    except:
        pass
if not font:
    font = ImageFont.load_default()

def draw_rounded_rect(draw, xy, rad, fill):
    x0, y0, x1, y1 = xy
    draw.rectangle([x0, y0 + rad, x1, y1 - rad], fill=fill)
    draw.rectangle([x0 + rad, y0, x1 - rad, y1], fill=fill)
    draw.pieslice([x0, y0, x0 + rad * 2, y0 + rad * 2], 180, 270, fill=fill)
    draw.pieslice([x1 - rad * 2, y0, x1, y0 + rad * 2], 270, 360, fill=fill)
    draw.pieslice([x0, y1 - rad * 2, x0 + rad * 2, y1], 90, 180, fill=fill)
    draw.pieslice([x1 - rad * 2, y1 - rad * 2, x1, y1], 0, 90, fill=fill)

def add_corners(im, rad):
    circle = Image.new('L', (rad * 2, rad * 2), 0)
    draw = ImageDraw.Draw(circle)
    draw.ellipse((0, 0, rad * 2 - 1, rad * 2 - 1), fill=255)
    alpha = Image.new('L', im.size, 255)
    w, h = im.size
    alpha.paste(circle.crop((0, 0, rad, rad)), (0, 0))
    alpha.paste(circle.crop((0, rad, rad, rad * 2)), (0, h - rad))
    alpha.paste(circle.crop((rad, 0, rad * 2, rad)), (w - rad, 0))
    alpha.paste(circle.crop((rad, rad, rad * 2, rad * 2)), (w - rad, h - rad))
    im.putalpha(alpha)
    return im

canvas = create_gradient()
draw = ImageDraw.Draw(canvas)

# Left Side: Logo and Text
logo_path = "/Users/rameez/Desktop/MANA YATRA/Flutter/rider/assets/screenshots/app_logo.png"
if os.path.exists(logo_path):
    try:
        logo = Image.open(logo_path).convert("RGBA")
        logo.thumbnail((180, 180), Image.Resampling.LANCZOS)
        canvas.paste(logo, (90, 70), logo)
    except Exception as e:
        print(f"Error loading logo: {e}")
else:
    print(f"Warning: Logo not found at {logo_path}")

caption = "CHOOSE YOUR FARE.\nRIDE FAIR."
lines = caption.split('\n')
text_y = 280
for line in lines:
    draw.text((90, text_y), line, font=font, fill=(255, 255, 255))
    text_y += font_size + 15

# Right Side: Phone Mockup
screenshot_path = "/Users/rameez/Desktop/MANA YATRA/Flutter/rider/assets/screenshots/home_page.jpg.jpeg"
if os.path.exists(screenshot_path):
    try:
        screenshot = Image.open(screenshot_path).convert("RGBA")
        
        # Calculate aspect ratios
        scale = 0.38
        phone_w = int(852 * scale)
        bezel = int(36 * scale)
        screen_w = phone_w - (bezel * 2)
        
        aspect_ratio = screenshot.height / screenshot.width
        screen_h = int(screen_w * aspect_ratio)
        
        phone_h = screen_h + (bezel * 2)
        
        phone_rad = int(70 * scale)
        screen_rad = int(40 * scale)
        button_w = max(1, int(6 * scale))
        
        # Position: Center it horizontally on the right side, flow off the bottom edge
        phone_x = W - phone_w - 90
        phone_y = 60
        
        # Create Device Layer
        device_img = Image.new('RGBA', (W, H), (0,0,0,0))
        dev_draw = ImageDraw.Draw(device_img)
        
        # Phone Shadow
        shadow_img = Image.new('RGBA', (W, H), (0,0,0,0))
        shadow_draw = ImageDraw.Draw(shadow_img)
        draw_rounded_rect(shadow_draw, [phone_x, phone_y + 15, phone_x + phone_w, phone_y + phone_h + 15], phone_rad, (0, 0, 0, 120))
        shadow_img = shadow_img.filter(ImageFilter.GaussianBlur(15))
        canvas.paste(shadow_img, (0,0), shadow_img)
        
        # Phone Body
        draw_rounded_rect(dev_draw, [phone_x, phone_y, phone_x + phone_w, phone_y + phone_h], phone_rad, (20, 20, 25, 255))
        
        # Inner Screen Bezel Area
        draw_rounded_rect(dev_draw, [phone_x + bezel-1, phone_y + bezel-1, phone_x + phone_w - bezel+1, phone_y + phone_h - bezel+1], screen_rad+1, (0, 0, 0, 255))
        
        # Buttons
        dev_draw.rectangle([phone_x + phone_w, phone_y + int(300*scale), phone_x + phone_w + button_w, phone_y + int((300+100)*scale)], fill=(40,40,45,255))
        dev_draw.rectangle([phone_x - button_w, phone_y + int(200*scale), phone_x, phone_y + int((200+70)*scale)], fill=(40,40,45,255))
        dev_draw.rectangle([phone_x - button_w, phone_y + int(290*scale), phone_x, phone_y + int((290+70)*scale)], fill=(40,40,45,255))
        
        canvas.paste(device_img, (0,0), device_img)
        
        # Screenshot
        screenshot = screenshot.resize((screen_w, screen_h), Image.Resampling.LANCZOS)
        screenshot = add_corners(screenshot, screen_rad)
        canvas.paste(screenshot, (phone_x + bezel, phone_y + bezel), screenshot)
        
    except Exception as e:
        print(f"Error drawing mockup: {e}")
else:
    print(f"Warning: Screenshot not found at {screenshot_path}")

outpath = "/Users/rameez/Desktop/MANA YATRA/Flutter/rider/assets/screenshots/feature_graphic.png"
canvas.convert('RGB').save(outpath, quality=100)
print(f"Generated Feature Graphic at: {outpath}")
