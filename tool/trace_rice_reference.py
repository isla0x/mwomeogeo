"""Trace the approved rice artwork without redesigning its silhouette or eyes.

Dev-only requirements: Pillow, numpy, scipy, contourpy; matplotlib for --render.
The source JPEG is kept unchanged; this emits Flutter-native cubic paths.
"""
from pathlib import Path
import hashlib
import re
import sys

import numpy as np
from PIL import Image
from scipy import ndimage
from scipy.interpolate import BSpline, splprep
from contourpy import contour_generator

root = Path(__file__).resolve().parents[1]
source = root / 'design/rice-widget-reference.jpeg'
pixels = np.asarray(Image.open(source).convert('RGB'))[124:296, 80:335]
dark = (pixels[:, :, 0] < 170) & (pixels[:, :, 1] < 120) & (pixels[:, :, 2] < 100)
labels, count = ndimage.label(dark)
areas = np.bincount(labels.ravel())
areas[0] = 0
outline = labels == areas.argmax()
silhouette = ndimage.binary_fill_holes(outline)
ys, xs = np.where(silhouette)
left, right = xs.min() - .5, xs.max() + .5
top, bottom = ys.min() - .5, ys.max() + .5
scale = 88 / (right - left)
cocoa = np.median(pixels[ndimage.binary_erosion(outline)], axis=0).astype(int)


def curve(mask):
    contours = contour_generator(z=mask.astype(float)).lines(.5)
    return max(contours, key=lambda p: abs(np.sum(p[:-1, 0] * p[1:, 1] - p[1:, 0] * p[:-1, 1])))


def transform(point):
    x, y = point
    return (6 + (x - left) * scale, 50 + (y - (top + bottom) / 2) * scale)


def dart_path(mask):
    points = curve(mask)
    tck, _ = splprep(points.T, s=len(points) * .16, per=True)
    t, coefficients, degree = tck
    spline = BSpline(t, np.array(coefficients).T, degree)
    derivative = spline.derivative()
    knots = np.unique(t[degree:-degree])
    commands = []
    start = transform(spline(knots[0]))
    commands.append(f'      ..moveTo({start[0]:.3f}, {start[1]:.3f})')
    for a, b in zip(knots[:-1], knots[1:]):
        h = (b - a) / 3
        c1 = transform(spline(a) + h * derivative(a))
        c2 = transform(spline(b) - h * derivative(b))
        end = transform(spline(b))
        values = ', '.join(f'{n:.3f}' for pair in (c1, c2, end) for n in pair)
        commands.append(f'      ..cubicTo({values})')
    return '\n'.join(commands) + '\n      ..close()'


shapes = [(silhouette, None)]
holes, hole_count = ndimage.label(silhouette & ~dark)
for i in range(1, hole_count + 1):
    region = holes == i
    if region.sum() < 20:
        continue
    color = np.median(pixels[ndimage.binary_erosion(region, iterations=2)], axis=0).astype(int)
    shapes.append((region, color))
for i in range(1, count + 1):
    if areas[i] > 20 and not np.array_equal(labels == i, outline):
        shapes.append((labels == i, None))

body = [
    '// Generated from the approved reference by tool/trace_rice_reference.py.',
    '// Source SHA256: ' + hashlib.sha256(source.read_bytes()).hexdigest(),
    "import 'package:flutter/material.dart';",
    '',
    'void paintRiceReference(Canvas canvas, {Color? ink}) {',
    '  final cocoa = ink ?? const Color(0xff' + ''.join(f'{v:02x}' for v in cocoa) + ');',
]
for mask, color in shapes:
    fill = 'cocoa' if color is None else 'const Color(0xff' + ''.join(f'{v:02x}' for v in color) + ')'
    body.extend(['  canvas.drawPath(', '    Path()', dart_path(mask) + ',', f'    Paint()..color = {fill},', '  );'])
body.append('}')
(root / 'lib/rice_reference.dart').write_text('\n'.join(body) + '\n')
print(f'Traced {len(shapes)} original contours; aspect ratio {(bottom-top)/(right-left):.4f}.')

if '--render' in sys.argv:
    # Render these same cubic paths when the Flutter SDK is not installed.
    # No source pixels or artwork proportions are edited.
    from matplotlib.backends.backend_agg import FigureCanvasAgg
    from matplotlib.figure import Figure
    from matplotlib.path import Path as MplPath
    from matplotlib.patches import PathPatch
    from matplotlib.transforms import Affine2D

    for name, bg, factor, offset in [
        ('assets/brand/rice-friends.png', None, 10.24, 0),
        ('assets/app-icon.png', '#ffe7da', 8.2, 102),
    ]:
        figure = Figure(figsize=(10.24, 10.24), dpi=100)
        canvas = FigureCanvasAgg(figure)
        figure.patch.set_facecolor(bg or 'none')
        axis = figure.add_axes((0, 0, 1, 1))
        axis.set_xlim(0, 1024)
        axis.set_ylim(1024, 0)
        axis.set_axis_off()
        for mask, color in shapes:
            points, codes = [], []
            for line in dart_path(mask).splitlines():
                match = re.search(r'\.\.(moveTo|cubicTo)\((.*)\)', line)
                if not match:
                    continue
                values = [float(v.strip()) for v in match[2].split(',')]
                for j in range(0, len(values), 2):
                    points.append(values[j:j+2])
                    codes.append(MplPath.MOVETO if match[1] == 'moveTo' else MplPath.CURVE4)
            points.append(points[0])
            codes.append(MplPath.CLOSEPOLY)
            fill = (cocoa if color is None else color) / 255
            axis.add_patch(PathPatch(MplPath(points, codes), facecolor=fill, edgecolor='none',
                transform=Affine2D().scale(factor).translate(offset, offset) + axis.transData))
        canvas.draw()
        Image.fromarray(np.array(canvas.buffer_rgba())).save(root / name)
        figure.clear()
    print('Rendered original-contour master and transparent brand asset.')
