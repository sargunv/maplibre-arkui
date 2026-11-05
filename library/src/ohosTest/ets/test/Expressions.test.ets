import { describe, expect, it } from '@ohos/hypium';
import {
  StyleExpressionHandle, StyleExpressionInputs, StyleExpressionTypeKind
} from '@maplibre/native-ffi';
import {
  abs, add, all, any, call, cases, ceil, coalesce, concat, cubicBezier, divide, downcase, eq,
  Expression, exponential, featureState, floor, format, geometryType, get, globalState, gt, gte, has,
  heatmapDensity, id, image, interpolate, interpolateHcl, interpolateLab, JsonValue, linear,
  lineProgress, literal, lt, lte, match, max, min, mod, multiply, neq, not, pow, properties, rgb, rgba,
  round, sqrt, step, subtract, toBoolean, toColor, toNumber, toString, upcase, zoom
} from '@maplibre/arkui';

function point(properties: Record<string, JsonValue>): Record<string, JsonValue> {
  const geometry: Record<string, JsonValue> = { 'type': 'Point', 'coordinates': [0, 0] };
  return { 'type': 'Feature', 'id': 7, 'properties': properties, 'geometry': geometry };
}

// Parses an expression with FFI, which checks it as MapLibre Native does, and
// returns its result for `inputs` as JSON text. FFI takes the expression as
// is, through its toJSON().
function evaluate(expression: Expression, kind: number, inputs?: StyleExpressionInputs): string {
  const handle = StyleExpressionHandle.create(expression, { expectedType: { kind: kind } });
  try {
    return JSON.stringify(handle.evaluate(inputs));
  } finally {
    handle.release();
  }
}

function atZoom(zoomLevel: number): StyleExpressionInputs {
  return { zoom: zoomLevel };
}

function withFeature(properties: Record<string, JsonValue>): StyleExpressionInputs {
  return { feature: point(properties) };
}

export default function expressionsTest(): void {
  describe('Expression JSON', () => {
    it('writes plain values bare and arrays as literals', 0, () => {
      expect(eq(get('name'), 'a').toString()).assertEqual('["==",["get","name"],"a"]');
      expect(coalesce(get('n'), 1, true, null).toString())
        .assertEqual('["coalesce",["get","n"],1,true,null]');
      expect(literal(['Open Sans', 'Arial']).toString()).assertEqual('["literal",["Open Sans","Arial"]]');
      expect(new Expression(['get', 'x']).toString()).assertEqual('["get","x"]');
      expect(JSON.stringify(get('x'))).assertEqual('["get","x"]');
      expect(call('in', get('class'), literal(['a', 'b'])).toString())
        .assertEqual('["in",["get","class"],["literal",["a","b"]]]');
    });

    it('writes feature data and inputs', 0, () => {
      expect(get('name', properties()).toString()).assertEqual('["get","name",["properties"]]');
      expect(has('name').toString()).assertEqual('["has","name"]');
      expect(has('name', properties()).toString()).assertEqual('["has","name",["properties"]]');
      expect(featureState('hover').toString()).assertEqual('["feature-state","hover"]');
      expect(globalState('theme').toString()).assertEqual('["global-state","theme"]');
      expect(id().toString()).assertEqual('["id"]');
      expect(geometryType().toString()).assertEqual('["geometry-type"]');
      expect(zoom().toString()).assertEqual('["zoom"]');
      expect(heatmapDensity().toString()).assertEqual('["heatmap-density"]');
      expect(lineProgress().toString()).assertEqual('["line-progress"]');
    });

    it('writes ramps with flat stops', 0, () => {
      expect(interpolate(linear(), zoom(), [[0, 1], [10, get('size')]]).toString())
        .assertEqual('["interpolate",["linear"],["zoom"],0,1,10,["get","size"]]');
      expect(interpolate(exponential(2), zoom(), [[10, 1], [18, 32]]).toString())
        .assertEqual('["interpolate",["exponential",2],["zoom"],10,1,18,32]');
      expect(interpolate(cubicBezier(0.4, 0, 1, 1), zoom(), [[0, 0], [1, 1]]).toString())
        .assertEqual('["interpolate",["cubic-bezier",0.4,0,1,1],["zoom"],0,0,1,1]');
      expect(interpolateLab(linear(), zoom(), [[0, '#000'], [1, '#fff']]).toString())
        .assertEqual('["interpolate-lab",["linear"],["zoom"],0,"#000",1,"#fff"]');
      expect(step(get('n'), 'low', [[10, 'mid'], [100, 'high']]).toString())
        .assertEqual('["step",["get","n"],"low",10,"mid",100,"high"]');
    });

    it('writes match labels bare and case conditions in order', 0, () => {
      const color = match(get('class'), [['park', '#0f0'], [['lake', 'river'], '#00f']], '#ccc');
      expect(color.toString())
        .assertEqual('["match",["get","class"],"park","#0f0",["lake","river"],"#00f","#ccc"]');
      expect(match(get('rank'), [[[1, 2], 'top'], [3, 'mid']], 'low').toString())
        .assertEqual('["match",["get","rank"],[1,2],"top",3,"mid","low"]');
      expect(cases([[gt(get('mag'), 5), 'big'], [has('mag'), 'small']], 'none').toString())
        .assertEqual('["case",[">",["get","mag"],5],"big",["has","mag"],"small","none"]');
    });

    it('writes format options in style-spec names', 0, () => {
      const text = format(
        { text: get('name') },
        { text: 'b', fontScale: 0.8, textFont: literal(['Bold']), textColor: '#f00' },
      );
      expect(text.toString()).assertEqual('["format",["get","name"],{},"b",' +
        '{"font-scale":0.8,"text-font":["literal",["Bold"]],"text-color":"#f00"}]');
    });

    it('writes each operator with its arguments in order', 0, () => {
      const pairs: [Expression, string][] = [
        [neq(1, 2), '["!=",1,2]'], [lt(1, 2), '["<",1,2]'], [lte(1, 2), '["<=",1,2]'],
        [gt(1, 2), '[">",1,2]'], [gte(1, 2), '[">=",1,2]'], [not(true), '["!",true]'],
        [all(true, false), '["all",true,false]'], [any(true, false), '["any",true,false]'],
        [add(1, 2, 3), '["+",1,2,3]'], [subtract(1, 2), '["-",1,2]'],
        [multiply(1, 2), '["*",1,2]'], [divide(1, 2), '["/",1,2]'], [mod(1, 2), '["%",1,2]'],
        [pow(2, 3), '["^",2,3]'], [sqrt(4), '["sqrt",4]'], [abs(-1), '["abs",-1]'],
        [round(1.5), '["round",1.5]'], [floor(1.5), '["floor",1.5]'], [ceil(1.5), '["ceil",1.5]'],
        [min(1, 2), '["min",1,2]'], [max(1, 2), '["max",1,2]'],
        [toNumber(get('n'), 0), '["to-number",["get","n"],0]'], [toString(1), '["to-string",1]'],
        [toBoolean(1), '["to-boolean",1]'], [toColor('#f00'), '["to-color","#f00"]'],
        [concat('a', 'b'), '["concat","a","b"]'], [upcase('a'), '["upcase","a"]'],
        [downcase('A'), '["downcase","A"]'], [rgb(1, 2, 3), '["rgb",1,2,3]'],
        [rgba(1, 2, 3, 0.5), '["rgba",1,2,3,0.5]'], [image('park'), '["image","park"]'],
        [interpolateHcl(linear(), zoom(), [[0, '#000'], [1, '#fff']]),
          '["interpolate-hcl",["linear"],["zoom"],0,"#000",1,"#fff"]'],
      ];
      for (const pair of pairs) {
        expect(pair[0].toString()).assertEqual(pair[1]);
      }
    });

    it('keeps a copy of the values it was built from', 0, () => {
      const labels: string[] = ['lake'];
      const values: JsonValue[] = ['a'];
      const water = match(get('class'), [[labels, '#00f']], '#ccc');
      const names = literal(values);
      labels.push('river');
      values.push('b');
      expect(JSON.stringify(water)).assertEqual('["match",["get","class"],["lake"],"#00f","#ccc"]');
      expect(water.toString()).assertEqual(JSON.stringify(water));
      expect(JSON.stringify(names)).assertEqual('["literal",["a"]]');
    });

    it('compares by JSON', 0, () => {
      const a = interpolate(linear(), zoom(), [[0, 1], [10, get('size')]]);
      const b = interpolate(linear(), zoom(), [[0, 1], [10, get('size')]]);
      const c = interpolate(linear(), zoom(), [[0, 1], [10, get('width')]]);
      expect(a.equals(b)).assertTrue();
      expect(a.equals(c)).assertFalse();
      expect(a.toString() === b.toString()).assertTrue();
    });
  });

  describe('Expression in MapLibre Native', () => {
    const NUMBER = StyleExpressionTypeKind.number;
    const STRING = StyleExpressionTypeKind.string;
    const BOOLEAN = StyleExpressionTypeKind.boolean;
    const COLOR = StyleExpressionTypeKind.color;

    it('interpolates with zoom', 0, () => {
      const ramp = interpolate(linear(), zoom(), [[0, 0], [20, 100]]);
      expect(evaluate(ramp, NUMBER, atZoom(10))).assertEqual('50');
      expect(evaluate(ramp, NUMBER, atZoom(30))).assertEqual('100');
      const curve = interpolate(exponential(2), zoom(), [[0, 0], [2, 3]]);
      expect(Number(evaluate(curve, NUMBER, atZoom(1)))).assertClose(1, 0.000001);
      expect(evaluate(step(zoom(), 1, [[5, 2], [10, 3]]), NUMBER, atZoom(7))).assertEqual('2');
      // An ease-in curve: y is 0.3248 where x is 0.5.
      const eased = interpolate(cubicBezier(0.4, 0, 1, 1), zoom(), [[0, 0], [1, 1]]);
      expect(Number(evaluate(eased, NUMBER, atZoom(0.5)))).assertClose(0.3248, 0.001);
    });

    it('interpolates heatmap density and line progress', 0, () => {
      const ramp: StyleExpressionInputs = { colorRampParameter: 0.5 };
      const density = interpolate(linear(), heatmapDensity(), [[0, 0], [1, 10]]);
      expect(evaluate(density, NUMBER, ramp)).assertEqual('5');
      const progress = interpolate(linear(), lineProgress(), [[0, 0], [1, 10]]);
      expect(evaluate(progress, NUMBER, ramp)).assertEqual('5');
    });

    it('interpolates colors', 0, () => {
      const ramp = interpolate(linear(), zoom(), [[0, '#000000'], [10, rgb(255, 255, 255)]]);
      expect(evaluate(ramp, COLOR, atZoom(5))).assertEqual('["rgba",127.5,127.5,127.5,1]');
      // HCL round trips aren't exact, so this rounds the channels.
      const hcl = interpolateHcl(linear(), get('t'), [[0, '#ff0000'], [1, '#0000ff']]);
      const red = round(call('at', 0, call('to-rgba', hcl)));
      const blue = round(call('at', 2, call('to-rgba', hcl)));
      expect(evaluate(red, NUMBER, withFeature({ 't': 0 }))).assertEqual('255');
      expect(evaluate(blue, NUMBER, withFeature({ 't': 1 }))).assertEqual('255');
      // Halfway from red to yellow, green is 160 in HCL and 127.5 in RGB.
      const hclToYellow = interpolateHcl(linear(), get('t'), [[0, '#ff0000'], [1, '#ffff00']]);
      const green = round(call('at', 1, call('to-rgba', hclToYellow)));
      expect(evaluate(green, NUMBER, withFeature({ 't': 0.5 }))).assertEqual('160');
      // Halfway from black to white, gray is 119 in CIELAB and 127.5 in RGB.
      const lab = interpolateLab(linear(), get('t'), [[0, '#000000'], [1, '#ffffff']]);
      const gray = round(call('at', 0, call('to-rgba', lab)));
      expect(evaluate(gray, NUMBER, withFeature({ 't': 0.5 }))).assertEqual('119');
      expect(evaluate(rgba(255, 0, 0, 0.5), COLOR)).assertEqual('["rgba",255,0,0,0.5]');
      // A string is a color in CSS syntax, with alpha last. MapLibre keeps
      // colors premultiplied, so red comes back as 254.99998….
      const translucent = evaluate(new Expression('#ff000080'), COLOR);
      expect(translucent.startsWith('["rgba",254.99')).assertTrue();
      expect(translucent.endsWith(',0,0,0.5]')).assertTrue();
      expect(evaluate(toColor(get('c'), '#00f'), COLOR, withFeature({ 'c': 'nope' })))
        .assertEqual('["rgba",0,0,255,1]');
    });

    it('matches a feature property', 0, () => {
      const color = match(get('class'), [['park', 'green'], [['lake', 'river'], 'blue']], 'gray');
      expect(evaluate(color, STRING, withFeature({ 'class': 'river' }))).assertEqual('"blue"');
      expect(evaluate(color, STRING, withFeature({ 'class': 'park' }))).assertEqual('"green"');
      expect(evaluate(color, STRING, withFeature({ 'class': 'road' }))).assertEqual('"gray"');
      const size = step(get('population'), 2, [[1000, 4], [100000, 8]]);
      expect(evaluate(size, NUMBER, withFeature({ 'population': 5000 }))).assertEqual('4');
    });

    it('picks the first true case', 0, () => {
      // A comparison fails on a missing property, so `has` comes first.
      const label = cases([[not(has('mag')), 'none'], [gt(get('mag'), 5), 'big']], 'small');
      expect(evaluate(label, STRING, withFeature({ 'mag': 6 }))).assertEqual('"big"');
      expect(evaluate(label, STRING, withFeature({ 'mag': 3 }))).assertEqual('"small"');
      expect(evaluate(label, STRING, withFeature({}))).assertEqual('"none"');
      const first = coalesce(get('a'), get('b'), 'c');
      expect(evaluate(first, STRING, withFeature({ 'b': 'b' }))).assertEqual('"b"');
    });

    it('reads feature state, global state, and the feature', 0, () => {
      const state: Record<string, JsonValue> = { 'hover': true };
      const opacity = cases([[eq(featureState('hover'), true), 1]], 0.5);
      const inputs: StyleExpressionInputs = { feature: point({}), featureState: state };
      expect(evaluate(opacity, NUMBER, inputs)).assertEqual('1');
      expect(evaluate(opacity, NUMBER, withFeature({}))).assertEqual('0.5');
      const global: Record<string, JsonValue> = { 'scale': 3 };
      expect(evaluate(multiply(globalState('scale'), 2), NUMBER, { globalState: global })).assertEqual('6');
      expect(evaluate(id(), NUMBER, withFeature({}))).assertEqual('7');
      expect(evaluate(geometryType(), STRING, withFeature({}))).assertEqual('"Point"');
      const props = withFeature({ 'a': 'x' });
      expect(evaluate(get('a', properties()), STRING, props)).assertEqual('"x"');
      expect(evaluate(has('b', properties()), BOOLEAN, props)).assertEqual('false');
    });

    it('computes math', 0, () => {
      const inputs = withFeature({ 'a': 3, 'b': -2.5 });
      expect(evaluate(add(multiply(get('a'), 2), 1), NUMBER, inputs)).assertEqual('7');
      expect(evaluate(subtract(get('a'), divide(9, get('a'))), NUMBER, inputs)).assertEqual('0');
      const b = get('b');
      expect(evaluate(add(mod(7, get('a')), pow(2, get('a')), sqrt(16)), NUMBER, inputs))
        .assertEqual('13');
      // 2.5 - 3 - 3 - 2: round takes halves away from zero.
      expect(evaluate(add(abs(b), round(b), floor(b), ceil(b)), NUMBER, inputs)).assertEqual('-5.5');
      expect(evaluate(subtract(max(get('a'), 5, 1), min(get('a'), 5, 1)), NUMBER, inputs))
        .assertEqual('4');
    });

    it('compares and combines booleans', 0, () => {
      const inputs = withFeature({ 'a': 3, 'name': 'x' });
      const test = all(gte(get('a'), 3), lte(get('a'), 3), not(lt(get('a'), 3)), neq(get('name'), 'y'),
        any(false, eq(get('name'), 'x')));
      expect(evaluate(test, BOOLEAN, inputs)).assertEqual('true');
      expect(evaluate(any(has('missing'), toBoolean(0)), BOOLEAN, inputs)).assertEqual('false');
      const within = call('in', get('name'), literal(['x', 'y']));
      expect(evaluate(within, BOOLEAN, inputs)).assertEqual('true');
    });

    it('converts and joins strings', 0, () => {
      const inputs = withFeature({ 'name': 'Main St', 'ref': 42, 'n': '12' });
      const label = concat(upcase(get('name')), ' (', toString(get('ref')), ') ', downcase('X'));
      expect(evaluate(label, STRING, inputs)).assertEqual('"MAIN ST (42) x"');
      expect(evaluate(add(toNumber(get('n')), 1), NUMBER, inputs)).assertEqual('13');
    });

    it('parses formatted text, images, and literals', 0, () => {
      const text = format({ text: get('name') }, { text: 'b', fontScale: 0.8, textColor: '#f00' });
      expect(evaluate(text, StyleExpressionTypeKind.formatted, withFeature({ 'name': 'a' })))
        .assertEqual('["format","a",{},"b",{"font-scale":0.8,"text-color":["rgba",255,0,0,1]}]');
      const icon = image(get('icon'));
      const iconInputs: StyleExpressionInputs = {
        feature: point({ 'icon': 'park' }), availableImages: ['park']
      };
      expect(evaluate(icon, StyleExpressionTypeKind.image, iconInputs))
        .assertEqual('{"available":true,"name":"park"}');
      expect(evaluate(literal(['Open Sans', 'Arial']), StyleExpressionTypeKind.value))
        .assertEqual('["Open Sans","Arial"]');
      expect(evaluate(new Expression(['upcase', 'raw']), STRING)).assertEqual('"RAW"');
    });

    it('rejects an expression of the wrong type', 0, () => {
      let threw = false;
      try {
        evaluate(rgb(1, 2, 3), NUMBER);
      } catch (error) {
        threw = true;
      }
      expect(threw).assertTrue();
    });
  });
}
