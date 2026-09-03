#!/usr/bin/env python3
import os
import sys
import json
import hashlib
import argparse

os.environ["OPENCV_LOG_LEVEL"] = "SILENT"
import cv2

def get_cache_path(img_path: str) -> str:
    cache_dir = os.path.expanduser("~/.cache/wallpapers/focal")
    os.makedirs(cache_dir, exist_ok=True)
    m = hashlib.md5(img_path.encode("utf-8")).hexdigest()
    return os.path.join(cache_dir, f"{m}.json")

def detect_focal_point(image_path: str):
    if not os.path.exists(image_path):
        return {"has_face": False, "focal_x": 0.5, "focal_y": 0.5, "face_count": 0}

    # Check cache first
    cache_file = get_cache_path(image_path)
    if os.path.exists(cache_file):
        try:
            with open(cache_file, "r") as f:
                data = json.load(f)
                if "focal_x" in data and "focal_y" in data:
                    return data
        except Exception:
            pass

    img = cv2.imread(image_path)
    if img is None:
        return {"has_face": False, "focal_x": 0.5, "focal_y": 0.5, "face_count": 0}

    orig_h, orig_w = img.shape[:2]
    # Downscale for fast detection (max dimension 1024)
    scale = 1.0
    max_dim = max(orig_w, orig_h)
    if max_dim > 1024:
        scale = 1024.0 / max_dim
        small = cv2.resize(img, (int(orig_w * scale), int(orig_h * scale)))
    else:
        small = img

    gray = cv2.cvtColor(small, cv2.COLOR_BGR2GRAY)
    gray = cv2.equalizeHist(gray)

    # 1. Try frontal face Haar cascade
    face_cascade = cv2.CascadeClassifier(os.path.join(cv2.data.haarcascades, "haarcascade_frontalface_default.xml"))
    faces = face_cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=4, minSize=(28, 28))

    # 2. Try profile face cascade if no frontal faces found
    if len(faces) == 0:
        profile_cascade = cv2.CascadeClassifier(os.path.join(cv2.data.haarcascades, "haarcascade_profileface.xml"))
        faces = profile_cascade.detectMultiScale(gray, scaleFactor=1.1, minNeighbors=4, minSize=(28, 28))

    sw, sh = int(orig_w * scale), int(orig_h * scale)

    if len(faces) > 0:
        # Pick the most prominent face (largest area) or center of largest
        best_face = None
        max_area = 0
        for (x, y, w, h) in faces:
            area = w * h
            if area > max_area:
                max_area = area
                best_face = (x, y, w, h)

        fx, fy, fw, fh = best_face
        # Normalized coordinates [0.0, 1.0]
        focal_x = (fx + fw / 2.0) / sw
        focal_y = (fy + fh / 2.0) / sh

        res = {
            "has_face": True,
            "focal_x": round(float(focal_x), 4),
            "focal_y": round(float(focal_y), 4),
            "face_count": len(faces),
            "face_width_rel": round(float(fw / sw), 4),
            "face_height_rel": round(float(fh / sh), 4),
        }
    else:
        # Fallback to center
        res = {
            "has_face": False,
            "focal_x": 0.5,
            "focal_y": 0.5,
            "face_count": 0
        }

    # Save to cache
    try:
        with open(cache_file, "w") as f:
            json.dump(res, f)
    except Exception:
        pass

    return res

def main():
    parser = argparse.ArgumentParser(description="Detect face / focal point in wallpaper")
    parser.add_argument("image_path", help="Path to wallpaper image")
    args = parser.parse_args()

    result = detect_focal_point(args.image_path)
    print(json.dumps(result))

if __name__ == "__main__":
    main()
