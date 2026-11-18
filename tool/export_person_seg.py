#!/usr/bin/env python3
"""Xuất model phân đoạn người (DeepLabV3-MobileNetV3, lớp "person" của VOC) sang ONNX.

Chạy trên máy có internet (torch và torchvision tải trọng số lần đầu):
  pip install torch torchvision onnx
  python3 tool/export_person_seg.py --out assets/models/person_seg.onnx

Đầu vào: RGB 256x256, chia 255, chuẩn hoá ImageNet (khớp PersonSegmenter).
Đầu ra: logit, shape [1, 1, 256, 256]; dương nghĩa là người.
"""
import argparse

import torch
from torchvision.models.segmentation import (
    DeepLabV3_MobileNet_V3_Large_Weights,
    deeplabv3_mobilenet_v3_large,
)

PERSON_CLASS = 15  # VOC: 0 nền, 15 người


class PersonMask(torch.nn.Module):
    def __init__(self, m):
        super().__init__()
        self.m = m

    def forward(self, x):
        return self.m(x)["out"][:, PERSON_CLASS : PERSON_CLASS + 1]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="assets/models/person_seg.onnx")
    args = ap.parse_args()

    m = deeplabv3_mobilenet_v3_large(
        weights=DeepLabV3_MobileNet_V3_Large_Weights.DEFAULT
    ).eval()
    x = torch.randn(1, 3, 256, 256)
    torch.onnx.export(
        PersonMask(m),
        x,
        args.out,
        input_names=["input"],
        output_names=["mask"],
        dynamic_axes={"input": {0: "batch"}, "mask": {0: "batch"}},
        opset_version=13,
    )
    print("xong:", args.out)


if __name__ == "__main__":
    main()
