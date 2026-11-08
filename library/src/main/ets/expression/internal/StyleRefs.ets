// The resource colors and images that an expression uses. A map adds them to
// each style that it applies the expression to: a color as a global state
// property, which follows the color mode, and an image under a reserved ID.
// A weak table keeps them off the public Expression class.

import { CheckedImageOptions } from '../../content/internal/StyleImages';
import { StyleImageSource } from '../../content/StyleImage';

// A resource color, under the global state name that the expression reads.
export class ColorRef {
  readonly name: string;
  readonly color: Resource;

  constructor(name: string, color: Resource) {
    this.name = name;
    this.color = color;
  }
}

// An image, under the ID that the expression names.
export class ImageRef {
  readonly name: string;
  readonly source: StyleImageSource;
  readonly options: CheckedImageOptions;

  constructor(name: string, source: StyleImageSource, options: CheckedImageOptions) {
    this.name = name;
    this.source = source;
    this.options = options;
  }

  // Whether ArkUI draws the image, so a new color mode can change it.
  get drawn(): boolean {
    return !isPixelMap(this.source);
  }
}

export type StyleRef = ColorRef | ImageRef;

const COLOR_PREFIX = 'maplibre-arkui:color:';
const IMAGE_PREFIX = 'maplibre-arkui-image:';

const refs = new WeakMap<Object, StyleRef[]>();
// A number for each pixel map and drawable descriptor, which names its image.
const objectIds = new WeakMap<Object, number>();
let nextObjectId = 0;

// The resource colors and images that `value` uses, if it's an expression.
export function refsOf(value: Object | null | undefined): StyleRef[] {
  return value === null || value === undefined ? [] : refs.get(value) ?? [];
}

// Gives `expression` the refs of `inputs`, once each.
export function attachRefs(expression: Object, inputs: Object[]): void {
  const merged = new Map<string, StyleRef>();
  for (const input of inputs) {
    for (const ref of refsOf(input)) {
      merged.set(ref.name, ref);
    }
  }
  if (merged.size > 0) {
    refs.set(expression, Array.from(merged.values()));
  }
}

export function setRefs(expression: Object, list: StyleRef[]): void {
  refs.set(expression, list);
}

export function isResource(value: Object): boolean {
  const resource = value as Resource;
  return typeof resource.id === 'number' && typeof resource.bundleName === 'string';
}

// Whether `value` is a pixel map, not a resource or a drawable descriptor.
export function isPixelMap(value: Object): boolean {
  if (isResource(value)) {
    return false;
  }
  return typeof (value as Record<string, Object>)['readPixelsToBufferSync'] === 'function';
}

function resourceKey(resource: Resource): string {
  const count: number = resource.params?.length ?? 0;
  return `${resource.bundleName}/${resource.moduleName}/${resource.id}` +
    (count === 0 ? '' : `/${JSON.stringify(resource.params)}`);
}

// The global state name of a resource color.
export function colorName(color: Resource): string {
  return `${COLOR_PREFIX}${resourceKey(color)}`;
}

// The style image ID of an image: the same for the same resource, and for the
// same pixel map or drawable descriptor.
export function imageName(source: StyleImageSource, options: CheckedImageOptions): string {
  let key: string;
  if (isResource(source)) {
    key = `r/${resourceKey(source as Resource)}`;
  } else {
    let id = objectIds.get(source);
    if (id === undefined) {
      id = nextObjectId++;
      objectIds.set(source, id);
    }
    key = `o/${id}`;
  }
  return `${IMAGE_PREFIX}${key}/${options.key}`;
}
