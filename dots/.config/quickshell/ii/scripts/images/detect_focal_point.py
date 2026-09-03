#!/usr/bin/env python3
import os
import sys
import json
import hashlib
import argparse
import numpy as np

os.environ["OPENCV_LOG_LEVEL"] = "SILENT"
import cv2

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.append(SCRIPT_DIR)
try:
    from yolox import YoloX
except ImportError:
    YoloX = None

MODELS_DIR = os.path.join(SCRIPT_DIR, "models")
YUNET_MODEL_PATH = os.path.join(MODELS_DIR, "face_detection_yunet_2023mar.onnx")
YOLOX_MODEL_PATH = os.path.join(MODELS_DIR, "object_detection_yolox_2022nov_int8.onnx")

COCO_CLASSES = [
    'person', 'bicycle', 'car', 'motorcycle', 'airplane', 'bus', 'train', 'truck', 'boat',
    'traffic light', 'fire hydrant', 'stop sign', 'parking meter', 'bench', 'bird', 'cat',
    'dog', 'horse', 'sheep', 'cow', 'elephant', 'bear', 'zebra', 'giraffe', 'backpack',
    'umbrella', 'handbag', 'tie', 'suitcase', 'frisbee', 'skis', 'snowboard', 'sports ball',
    'kite', 'baseball bat', 'baseball glove', 'skateboard', 'surfboard', 'tennis racket',
    'bottle', 'wine glass', 'cup', 'fork', 'knife', 'spoon', 'bowl', 'banana', 'apple',
    'sandwich', 'orange', 'broccoli', 'carrot', 'hot dog', 'pizza', 'donut', 'cake',
    'chair', 'couch', 'potted plant', 'bed', 'dining table', 'toilet', 'tv', 'laptop',
    'mouse', 'remote', 'keyboard', 'cell phone', 'microwave', 'oven', 'toaster', 'sink',
    'refrigerator', 'book', 'clock', 'vase', 'scissors', 'teddy bear', 'hair drier', 'toothbrush'
]

def get_cache_path(img_path: str) -> str:
    cache_dir = os.path.expanduser("~/.cache/wallpapers/focal")
    os.makedirs(cache_dir, exist_ok=True)
    m = hashlib.md5(img_path.encode("utf-8")).hexdigest()
    return os.path.join(cache_dir, f"{m}.json")

def detect_faces(img, orig_w, orig_h):
    """
    Tier 1: Deep Learning Face Detection (YuNet) with Haar Cascade fallback
    """
    faces_found = []

    # 1. Try YuNet ONNX
    if os.path.exists(YUNET_MODEL_PATH):
        try:
            target_dim = 1024
            scale = min(1.0, float(target_dim) / max(orig_w, orig_h))
            nw, nh = max(1, int(orig_w * scale)), max(1, int(orig_h * scale))
            small = cv2.resize(img, (nw, nh))

            yunet = cv2.FaceDetectorYN.create(YUNET_MODEL_PATH, "", (nw, nh), score_threshold=0.5)
            _, dets = yunet.detect(small)
            if dets is not None and len(dets) > 0:
                for d in dets:
                    fx, fy, fw, fh = d[:4]
                    score = float(d[-1])
                    w_rel = float(fw / nw)
                    h_rel = float(fh / nh)
                    area = w_rel * h_rel
                    # Ignore microscopic artifacts (e.g. less than 3% of image dimension)
                    if max(w_rel, h_rel) < 0.05 and score < 0.65:
                        continue
                    cx = (fx + fw / 2.0) / nw
                    cy = (fy + fh / 2.0) / nh
                    faces_found.append({
                        "cx": float(cx),
                        "cy": float(cy),
                        "w": w_rel,
                        "h": h_rel,
                        "area": float(area),
                        "score": score
                    })
        except Exception:
            pass

    if len(faces_found) > 0:
        best = max(faces_found, key=lambda f: f["area"])
        return {
            "has_subject": True,
            "focal_type": "face",
            "focal_x": round(float(np.clip(best["cx"], 0.0, 1.0)), 4),
            "focal_y": round(float(np.clip(best["cy"], 0.0, 1.0)), 4),
            "width_rel": round(float(best["w"]), 4),
            "height_rel": round(float(best["h"]), 4),
            "count": len(faces_found)
        }

    return None

def detect_objects(img, orig_w, orig_h):
    """
    Tier 2: Neural Object Detection (YOLOX) for cars, trains, animals, bicycles, etc.
    """
    if YoloX is None or not os.path.exists(YOLOX_MODEL_PATH):
        return None

    try:
        yolox = YoloX(YOLOX_MODEL_PATH, confThreshold=0.35)
        # Letterbox to 640x640
        scale = min(640.0 / orig_h, 640.0 / orig_w)
        nh, nw = int(orig_h * scale), int(orig_w * scale)
        resized = cv2.resize(img, (nw, nh))
        padded = np.full((640, 640, 3), 114, dtype=np.uint8)
        padded[:nh, :nw] = resized

        dets = yolox.infer(padded)
        if len(dets) == 0:
            return None

        objects = []
        for d in dets:
            bx, by, bw, bh, score, cls_id = d
            cls_name = COCO_CLASSES[int(cls_id)] if int(cls_id) < len(COCO_CLASSES) else "object"
            cx = (bx + bw / 2.0) / scale / orig_w
            cy = (by + bh / 2.0) / scale / orig_h
            w_rel = (bw / scale) / orig_w
            h_rel = (bh / scale) / orig_h
            area = w_rel * h_rel

            # Ignore extreme perimeter slivers (near outer 8% screen edges) unless large
            dist_from_center = np.hypot(cx - 0.5, cy - 0.5)
            if (cy > 0.90 or cy < 0.08 or cx < 0.08 or cx > 0.92) and area < 0.03:
                continue

            # Ignore microscopic noise (< 0.8% area)
            if area < 0.008:
                continue

            # Distant background clutter (< 1.5% area): only keep if it is centrally composed and confident
            if area < 0.015 and (dist_from_center > 0.28 or score < 0.60):
                continue

            objects.append({
                "label": cls_name,
                "cx": float(cx),
                "cy": float(cy),
                "w": float(w_rel),
                "h": float(h_rel),
                "area": float(area),
                "score": float(score)
            })

        if len(objects) > 0:
            # Pick largest/most prominent object
            best = max(objects, key=lambda o: o["area"])
            return {
                "has_subject": True,
                "focal_type": best["label"],
                "focal_x": round(float(np.clip(best["cx"], 0.0, 1.0)), 4),
                "focal_y": round(float(np.clip(best["cy"], 0.0, 1.0)), 4),
                "width_rel": round(float(best["w"]), 4),
                "height_rel": round(float(best["h"]), 4),
                "count": len(objects)
            }
    except Exception:
        pass

    return None

def detect_focal_point(image_path: str):
    if not os.path.exists(image_path):
        return {"has_subject": False, "focal_type": "center", "focal_x": 0.5, "focal_y": 0.5, "width_rel": 0.3, "height_rel": 0.3, "count": 0}

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
        return {"has_subject": False, "focal_type": "center", "focal_x": 0.5, "focal_y": 0.5, "width_rel": 0.3, "height_rel": 0.3, "count": 0}

    orig_h, orig_w = img.shape[:2]

    face_res = detect_faces(img, orig_w, orig_h)
    obj_res = detect_objects(img, orig_w, orig_h)

    # If face is prominent (> 6% of image) or no prominent object, prioritize face
    # If face is tiny/ambiguous (< 6%) but there is a major object (like a train, car, plane), prioritize the major object
    final_res = None
    if face_res and obj_res:
        face_dim = max(face_res.get("width_rel", 0), face_res.get("height_rel", 0))
        obj_area = obj_res.get("width_rel", 0) * obj_res.get("height_rel", 0)
        face_area = face_res.get("width_rel", 0) * face_res.get("height_rel", 0)

        if face_dim < 0.06 and obj_area > (face_area * 10):
            final_res = obj_res
        else:
            final_res = face_res
    elif face_res:
        final_res = face_res
    elif obj_res:
        final_res = obj_res

    if final_res:
        try:
            with open(cache_file, "w") as f:
                json.dump(final_res, f)
        except Exception:
            pass
        return final_res

    # 3. Fallback: Center (0.5, 0.5) as requested
    center_res = {
        "has_subject": False,
        "focal_type": "center",
        "focal_x": 0.5,
        "focal_y": 0.5,
        "width_rel": 0.3,
        "height_rel": 0.3,
        "count": 0
    }
    try:
        with open(cache_file, "w") as f:
            json.dump(center_res, f)
    except Exception:
        pass
    return center_res

def main():
    parser = argparse.ArgumentParser(description="Deep Learning Face & Object Focal Point Detector")
    parser.add_argument("image_path", help="Path to wallpaper image")
    args = parser.parse_args()

    result = detect_focal_point(args.image_path)
    print(json.dumps(result))

if __name__ == "__main__":
    main()
