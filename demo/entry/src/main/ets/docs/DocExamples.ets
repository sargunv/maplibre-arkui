// Each guide example in a tab, so the demo build compiles every example file.
// The guides cut their snippets out of these files by `// #region` name.

import { EditStyleExample, StyleUrlExample, SwitchStyleExample } from './Styling';
import { CameraBoundsExample, CameraMovingExample, MoveCameraExample, ReadCameraExample, StartPositionExample, ViewportInsetsExample } from './Camera';
import { BelowLabelsExample, ExpressionLayerExample, GeoJsonExample, ImageExample, SdfImageExample } from './Layers';
import { CooperativeExample, LayerClickExample, MapClickExample, PanStartExample, RestrictExample } from './Interaction';
import { ClusterExample, HighlightExample, QueryRenderedExample } from './Features';
import { CustomControlsExample, MarkerExample, NoControlsExample, PointerPinExample, PresetExample } from './Controls';
import { FollowExample, HeadingExample, IndicatorExample, LocationExample } from './Location';
import { SnapshotExample, SnapshotOfMapExample } from './Snapshots';
import { DownloadExample } from './Offline';
import { AppStyleExample } from './Requests';
import { OnErrorExample } from './Errors';
import { EXPRESSION_VALUES } from './Expressions';

// Examples that aren't components only need to compile.
export const COMPILED_EXAMPLES: Object[] = EXPRESSION_VALUES;

@ComponentV2
export struct DocExamples {
  build() {
    NavDestination() {
      Tabs() {
        TabContent() {
          StyleUrlExample()
        }.tabBar('Style URL')
        TabContent() {
          SwitchStyleExample()
        }.tabBar('Switch style')
        TabContent() {
          EditStyleExample()
        }.tabBar('Edit style')
        TabContent() {
          StartPositionExample()
        }.tabBar('Start')
        TabContent() {
          MoveCameraExample()
        }.tabBar('Move')
        TabContent() {
          ReadCameraExample()
        }.tabBar('Read')
        TabContent() {
          CameraMovingExample()
        }.tabBar('Moving')
        TabContent() {
          ViewportInsetsExample()
        }.tabBar('Insets')
        TabContent() {
          CameraBoundsExample()
        }.tabBar('Bounds')
        TabContent() {
          GeoJsonExample()
        }.tabBar('GeoJSON')
        TabContent() {
          ExpressionLayerExample()
        }.tabBar('Expressions')
        TabContent() {
          BelowLabelsExample()
        }.tabBar('Below labels')
        TabContent() {
          ImageExample()
        }.tabBar('Image')
        TabContent() {
          SdfImageExample()
        }.tabBar('SDF image')
        TabContent() {
          RestrictExample()
        }.tabBar('Restrict')
        TabContent() {
          PanStartExample()
        }.tabBar('Pan start')
        TabContent() {
          MapClickExample()
        }.tabBar('Map click')
        TabContent() {
          LayerClickExample()
        }.tabBar('Layer click')
        TabContent() {
          CooperativeExample()
        }.tabBar('Cooperative')
        TabContent() {
          QueryRenderedExample()
        }.tabBar('Query')
        TabContent() {
          HighlightExample()
        }.tabBar('Highlight')
        TabContent() {
          ClusterExample()
        }.tabBar('Clusters')
        TabContent() {
          PresetExample()
        }.tabBar('Preset')
        TabContent() {
          NoControlsExample()
        }.tabBar('No controls')
        TabContent() {
          CustomControlsExample()
        }.tabBar('Custom controls')
        TabContent() {
          MarkerExample()
        }.tabBar('Marker')
        TabContent() {
          PointerPinExample()
        }.tabBar('Pointer pin')
        TabContent() {
          LocationExample()
        }.tabBar('Location')
        TabContent() {
          FollowExample()
        }.tabBar('Follow')
        TabContent() {
          HeadingExample()
        }.tabBar('Heading')
        TabContent() {
          IndicatorExample()
        }.tabBar('Indicator')
        TabContent() {
          SnapshotExample()
        }.tabBar('Snapshot')
        TabContent() {
          SnapshotOfMapExample()
        }.tabBar('Snapshot of map')
        TabContent() {
          DownloadExample()
        }.tabBar('Offline')
        TabContent() {
          AppStyleExample()
        }.tabBar('App style')
        TabContent() {
          OnErrorExample()
        }.tabBar('Errors')
      }
      .barMode(BarMode.Scrollable)
    }
    .title('Guide examples')
  }
}
