from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os
import math

directory = "/Users/rameez/Desktop/MANA YATRA/Flutter/rider/assets/screenshots"
output_dir = os.path.join(directory, "presentation")

if not os.path.exists(output_dir):
    os.makedirs(output_dir)

captions = {
    "driver_bids.jpg.jpeg": "COMPARE BIDS\n& CHOOSE FARE",
    "driver_matching_screen.jpg.jpeg": "FINDING NEARBY\nDRIVERS",
    "emergency_contacts.jpg.jpeg": "SAFETY FIRST\nCONTACTS",
    "profile.jpg.jpeg": "MANAGE YOUR\nPROFILE",
    "ride_booking.jpg.jpeg": "BOOK YOUR RIDE\nINSTANTLY",
    "ride_hisory.jpg.jpeg": "TRACK YOUR\nRIDE HISTORY",
    "set_your_route.jpg.jpeg": "SET YOUR DESTINATION\nEASILY",
    "support.jpg.jpeg": "24/7 CUSTOMER\nSUPPORT"
}

W, H = 1080, 1920

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
font_size = 90
font_paths = [
    "/System/Library/Fonts/Supplemental/Impact.ttf",
    "/System/Library/Fonts/Avenir Next.ttc",
    "/Library/Fonts/Arial Bold.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
]
for path in font_paths:
    try:
        # Avenir Next Bold is index 4 or 5 usually, Helvetica Bold is index 1
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

for filename, caption in captions.items():
    filepath = os.path.join(directory, filename)
    if not os.path.exists(filepath):
        continue
    
    canvas = create_gradient()
    draw = ImageDraw.Draw(canvas)
    
    # Draw text with drop shadow
    lines = caption.split('\n')
    text_y = 100
    for line in lines:
        try:
            text_bbox = draw.textbbox((0, 0), line, font=font)
            text_w = text_bbox[2] - text_bbox[0]
            text_h = text_bbox[3] - text_bbox[1]
        except AttributeError:
            text_w, text_h = draw.textsize(line, font=font)
        except Exception:
            text_w = len(line) * 45
            text_h = font_size
            
        text_x = (W - text_w) // 2
        draw.text((text_x, text_y), line, font=font, fill=(255, 255, 255))
        text_y += text_h + 30
    
    # Process screenshot
    screenshot = Image.open(filepath).convert("RGBA")
    
    # Dimensions for phone mockup
    screen_w = 780
    aspect_ratio = screenshot.height / screenshot.width
    screen_h = int(screen_w * aspect_ratio)
    
    bezel = 36
    phone_w = screen_w + (bezel * 2)
    phone_h = screen_h + (bezel * 2)
    phone_rad = 70
    screen_rad = 40
    
    phone_x = (W - phone_w) // 2
    phone_y = 420
    
    # Draw Phone Shadow
    shadow_img = Image.new('RGBA', (W, H), (0,0,0,0))
    shadow_draw = ImageDraw.Draw(shadow_img)
    shadow_offset_y = 40
    draw_rounded_rect(shadow_draw, [phone_x, phone_y + shadow_offset_y, phone_x + phone_w, phone_y + phone_h + shadow_offset_y], phone_rad, (0, 0, 0, 100))
    shadow_img = shadow_img.filter(ImageFilter.GaussianBlur(30))
    canvas.paste(shadow_img, (0,0), shadow_img)
    
    # Create Phone Device layer
    device_img = Image.new('RGBA', (W, H), (0,0,0,0))
    dev_draw = ImageDraw.Draw(device_img)
    
    # Phone Body (Dark Slate)
    draw_rounded_rect(dev_draw, [phone_x, phone_y, phone_x + phone_w, phone_y + phone_h], phone_rad, (20, 20, 25, 255))
    
    # Phone Inner Bezel/Screen Area (Black)
    draw_rounded_rect(dev_draw, [phone_x + bezel-2, phone_y + bezel-2, phone_x + phone_w - bezel+2, phone_y + phone_h - bezel+2], screen_rad+2, (0, 0, 0, 255))
    
    # Power Button
    button_w = 6
    button_h = 100
    dev_draw.rectangle([phone_x + phone_w, phone_y + 300, phone_x + phone_w + button_w, phone_y + 300 + button_h], fill=(40,40,45,255))
    # Volume Buttons
    dev_draw.rectangle([phone_x - button_w, phone_y + 200, phone_x, phone_y + 200 + 70], fill=(40,40,45,255))
    dev_draw.rectangle([phone_x - button_w, phone_y + 290, phone_x, phone_y + 290 + 70], fill=(40,40,45,255))
    
    # Paste device onto canvas
    canvas.paste(device_img, (0,0), device_img)
    
    # Prepare and paste screenshot
    try:
        screenshot = screenshot.resize((screen_w, screen_h), Image.Resampling.LANCZOS)
    except:
        screenshot = screenshot.resize((screen_w, screen_h), Image.ANTIALIAS)
    
    screenshot = add_corners(screenshot, screen_rad)
    canvas.paste(screenshot, (phone_x + bezel, phone_y + bezel), screenshot)
    
    outpath = os.path.join(output_dir, f"presentation_{filename}")
    canvas.convert('RGB').save(outpath, quality=95)
    print(f"Generated {outpath}")

print("All screenshots generated successfully.")
