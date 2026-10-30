import onnxruntime as ort

for p in [r"open-image-models\yolo-v9-t-384-license-plate-end2end\yolo-v9-t-384-license-plates-end2end.onnx",
          r"fast-plate-ocr\cct-xs-v1-global-model\cct_xs_v1_global.onnx"]:
    s = ort.InferenceSession(p, providers=["CPUExecutionProvider"])
    print("\n==", p)
    for i in s.get_inputs():  print("  IN ", i.name, i.shape, i.type)
    for o in s.get_outputs(): print("  OUT", o.name, o.shape, o.type)

print("\n== plate_config.yaml")
print(open(r"fast-plate-ocr\cct-xs-v1-global-model\cct_xs_v1_global_plate_config.yaml", encoding="utf-8").read())