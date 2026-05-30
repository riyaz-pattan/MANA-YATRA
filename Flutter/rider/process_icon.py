from PIL import Image, ImageChops

def trim(im):
    bg = Image.new(im.mode, im.size, im.getpixel((0,0)))
    diff = ImageChops.difference(im, bg)
    diff = ImageChops.add(diff, diff, 2.0, -100)
    bbox = diff.getbbox()
    if bbox:
        return im.crop(bbox)
    return im

def main():
    try:
        # Open original image
        img = Image.open('assets/images/logo/gaman.png').convert('RGB')
        
        # Trim white space
        trimmed = trim(img)
        
        # We want the text to be as wide as possible within the 1024 circle.
        # Let's set the target width to 900, which leaves a small 62px padding on each side.
        target_width = 900
        ratio = target_width / trimmed.size[0]
        new_size = (target_width, int(trimmed.size[1] * ratio))
        
        # Resize
        resized = trimmed.resize(new_size, Image.Resampling.LANCZOS)
        
        # Create new 1024x1024 white image
        final_img = Image.new('RGB', (1024, 1024), color='white')
        
        # Paste in center
        paste_x = (1024 - new_size[0]) // 2
        paste_y = (1024 - new_size[1]) // 2
        
        final_img.paste(resized, (paste_x, paste_y))
        
        # Save as gaman_app_icon.png
        final_img.save('assets/images/logo/gaman_app_icon.png')
        print("Image processed and saved.")
        
    except Exception as e:
        print(f"Error: {e}")

if __name__ == '__main__':
    main()
