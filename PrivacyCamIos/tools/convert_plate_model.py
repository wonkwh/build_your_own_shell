# 번호판 ONNX(end2end, NMS 포함) → NMS 를 뺀 Core ML(.mlpackage, FP16) 변환 + ONNX 대비 검증.
# uv venv --python 3.12 && uv pip install onnx onnx2torch "torch==2.7.0" "torchvision==0.22.0" coremltools numpy pillow onnxruntime
# python tools/convert_plate_model.py <license_plate_yolov9_t_384.onnx> MaskShare/Models/LicensePlateDetector.mlpackage <sample.jpg>
import sys, numpy as np, onnx, onnx.utils, torch, coremltools as ct, onnxruntime as ort
from onnx2torch import convert
src, out = sys.argv[1], sys.argv[2]
cut = "/model/model.22/Concat_5_output_0"
onnx.utils.extract_model(src, "plate_raw.onnx", ["images"], [cut])
m = convert(onnx.load("plate_raw.onnx")).eval()
x = torch.rand(1, 3, 384, 384)
with torch.no_grad():
    ref = ort.InferenceSession("plate_raw.onnx").run(None, {"images": x.numpy()})[0]
    got = m(x).numpy()
print("raw shape", ref.shape, "torch vs onnx max diff", np.abs(ref - got).max())
traced = torch.jit.trace(m, x)
ml = ct.convert(traced,
    inputs=[ct.ImageType(name="images", shape=(1, 3, 384, 384), scale=1/255.0, color_layout=ct.colorlayout.RGB)],
    outputs=[ct.TensorType(name="predictions")],
    compute_precision=ct.precision.FLOAT16,
    minimum_deployment_target=ct.target.iOS17)
ml.short_description = "License plate YOLOv9-t 384, no NMS. predictions [1,5,3024]: cx,cy,w,h,score in 384px letterbox space."
ml.save(out)
# Compare Core ML (FP16) to ONNX on a real image letterboxed with 114 gray.
from PIL import Image
img = Image.open(sys.argv[3]).convert("RGB"); s = min(384/img.width, 384/img.height)
r = img.resize((round(img.width*s), round(img.height*s)), Image.BILINEAR)
canvas = Image.new("RGB", (384, 384), (114,114,114)); canvas.paste(r, ((384-r.width)//2, (384-r.height)//2))
arr = np.asarray(canvas, dtype=np.float32).transpose(2,0,1)[None] / 255
o = ort.InferenceSession("plate_raw.onnx").run(None, {"images": arr})[0]
c = ct.models.MLModel(out).predict({"images": canvas})["predictions"]
print("coreml vs onnx score diff", np.abs(o[0,4]-c[0,4]).max(), "box diff", np.abs(o[0,:4]-c[0,:4]).max(), "top scores", np.sort(o[0,4])[-3:], np.sort(c[0,4])[-3:])
