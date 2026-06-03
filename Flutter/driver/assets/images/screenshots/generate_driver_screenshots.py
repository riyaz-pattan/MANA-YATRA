import os
from PIL import Image, ImageDraw, ImageFont

# Config
SCREENSHOTS_DIR = '/Users/rameez/Desktop/MANA YATRA/Flutter/driver/assets/images/screenshots'
OUTPUT_DIR = os.path.join(SCREENSHOTS_DIR, 'processed')
WIDTH, HEIGHT = 1080, 1920

if not os.path.exists(OUTPUT_DIR):
    os.makedirs(OUTPUT_DIR)

captions = {
    "ride_requests.jpg.jpeg": "RECEIVE RIDE REQUESTS",
    "place_your_bid.jpg.jpeg": "BID YOUR OWN FARE",
    "ride_in_progress.jpg.jpeg": "SMART NAVIGATION",
    "ride_success_screen.jpg.jpeg": "GET PAID INSTANTLY",
    "earnings_history.jpg.jpeg": "TRACK YOUR EARNINGS",
    "referal.jpg.jpeg": "REFER AND EARN",
    "support.jpg.jpeg": "24/7 DRIVER SUPPORT"
}

def create_gradient():
    # Premium Dark Gradient (Dark Grey to Black)
    base = Image.new('RGB', (WIDTH, HEIGHT), "#111111")
    top = Image.new('RGB', (WIDTH, HEIGHT), "#2b2b2b")
    mask = Image.new('L', (WIDTH, HEIGHT))
    mask_data = []
    for y in range(HEIGHT):
        mask_data.extend([int(255 * (y / HEIGHT))] * WIDTH)
    mask.putdata(mask_data)
    base.paste(top, (0, 0), mask)
    return base

def add_device_frame(img_path):
    screenshot = Image.open(img_path).convert("RGBA")
    
    # Calculate scale to fit inside 9:16 nicely
    target_w = 840
    ratio = target_w / screenshot.width
    target_h = int(screenshot.height * ratio)
    screenshot = screenshot.resize((target_w, target_h), Image.Resampling.LANCZOS)
    
    # Create simple rounded device frame (no notch, clean look)
    frame_padding = 14
    frame_w = target_w + (frame_padding * 2)
    frame_h = target_h + (frame_padding * 2)
    
    device = Image.new('RGBA', (frame_w, frame_h), (0,0,0,0))
    draw = ImageDraw.Draw(device)
    draw.rounded_rectangle([0, 0, frame_w, frame_h], radius=45, fill="#FFFFFF")
    
    # Paste screenshot inside frame
    device.paste(screenshot, (frame_padding, frame_padding), screenshot)
    return device

# Font setup
try:
    font_large = ImageFont.truetype("/System/Library/Fonts/Supplemental/Impact.ttf", 68)
except:
    try:
        font_large = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 68)
    except:
        font_large = ImageFont.load_default()

for filename, text in captions.items():
    filepath = os.path.join(SCREENSHOTS_DIR, filename)
    if not os.path.exists(filepath):
        print(f"File not found: {filename}")
        continue
        
    bg = create_gradient()
    draw = ImageDraw.Draw(bg)
    
    # Calculate text size
    bbox = draw.textbbox((0, 0), text, font=font_large)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    
    text_x = (WIDTH - text_w) // 2
    text_y = 180
    
    # Draw rounded rectangle behind text for contrast
    padding_x = 50
    padding_y = 30
    rect_coords = [
        text_x - padding_x, 
        text_y - padding_y, 
        text_x + text_w + padding_x, 
        text_y + text_h + padding_y + 10
    ]
    
    # App accent color #FFCC00 (Yellow) for the background pill
    draw.rounded_rectangle(rect_coords, radius=25, fill="#FFCC00")
    
    # Draw text (Solid black, NO shadow, bold and clear)
    draw.text((text_x, text_y), text, font=font_large, fill="#000000")
    
    # Add device frame
    device = add_device_frame(filepath)
    
    # Paste device onto background
    device_x = (WIDTH - device.width) // 2
    device_y = text_y + text_h + 160
    
    bg.paste(device, (device_x, device_y), device)
    
    # Save
    out_path = os.path.join(OUTPUT_DIR, filename)
    # Convert to RGB to save as JPEG
    bg_rgb = bg.convert('RGB')
    bg_rgb.save(out_path, format="JPEG", quality=95)
    print(f"Generated {out_path}")
