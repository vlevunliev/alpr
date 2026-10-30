import cv2
from fast_alpr import ALPR

alpr = ALPR(
    detector_model="yolo-v9-t-384-license-plate-end2end",
    ocr_model="cct-xs-v1-global-model",
)

frame = cv2.imread("kola.jpg")
for r in alpr.predict(frame):
    print(r.ocr.text, r.ocr.confidence)

cv2.imwrite("rezultat.jpg", alpr.draw_predictions(frame))