// Generated from spec/schema/sdui.schema.json by spec/tools/codegen.mjs — do not edit by hand.
// Other backend languages can generate equivalent types from the same schema
// (or spec/openapi.yaml) via `openapi-generator` or `quicktype`.

/** A full screen: its data dependencies, its content tree, and screen-level lifecycle hooks. */
export interface Screen {
  analytics?: AnalyticsTag;
  /**
   * How the host frames the screen. 'immersive' = edge-to-edge, no nav bar, fixed theme (the screen draws its own background/chrome).
   */
  chrome?: "standard" | "immersive";
  content: Component;
  data?: DataConfig;
  /** Stable screen identifier. Used for navigation targets, deep links and analytics. */
  id: string;
  /** Action run once the screen becomes visible (analytics, prefetch, etc.). */
  onAppear?: Action;
  onDisappear?: Action;
  /**
   * Pull-to-refresh behaviour. If present, the renderer attaches a refresh control that re-runs the named data sources.
   */
  refresh?: { sources?: string[]; };
  scrollBehavior?: ScrollBehavior;
  /**
   * Local, client-only state initialised when the screen appears. Keys are referenced as '$state.<key>'. Values are literals used as defaults.
   */
  state?: { [key: string]: unknown; };
  /**
   * An interactive-teaching coach prompt — a dismissible 'try this' card that onboards a newcomer with one concrete action and an instant result.
   */
  teach?: { task: string; title: string; };
  /** Navigation-bar title. May be a binding, e.g. '$data.product.title'. */
  title?: BindableString;
  /**
   * Nav-bar toolbar items pinned beside the title — the HIG home for search / filter / add. Unlike controls placed in the scroll body, these do NOT scroll away; they migrate into the compact nav bar as the large title collapses. Renders as iOS .toolbar items, Android TopAppBar actions, Aurora page-header buttons.
   */
  toolbar?: { leading?: ToolbarItem[]; trailing?: ToolbarItem[]; };
}

/** A single nav-bar toolbar button: an icon that fires an action. */
export interface ToolbarItem {
  /** VoiceOver label; falls back to the icon name. */
  accessibilityLabel?: string;
  /** Action dispatched on tap. */
  action?: Action;
  /** Icon / SF-Symbol name (mapped per platform). */
  icon: string;
}

/**
 * Scroll-reactive header for the whole screen: a large title (derived from the screen 'title') that shrinks and pins as you scroll, cross-fading into the nav bar, plus optional pull-to-reveal search. Set once per screen; the engine gives every scroll the same Apple-grade behaviour.
 */
export interface ScrollBehavior {
  /** Show the collapsing large title. Default true; false = a plain inline title. */
  largeTitle?: boolean;
  /**
   * How small the title shrinks before handing off to the nav bar, as a fraction of full size. Default 0.62.
   */
  minScale?: number;
  /** Cross-fade a compact title into the nav bar after collapse. Default true. */
  pinTitle?: boolean;
  /** Scroll distance (pt) over which the collapse completes. Default derived from the title height. */
  range?: number;
  /** Telegram-style search hidden above the title, revealed by pulling down at the top. */
  revealOnPull?: { bind?: string; placeholder?: string; threshold?: number; };
  /** Optional one-line subtitle under the large title. */
  subtitle?: BindableString;
}

interface ComponentBase {
  /** Optional stable id. Required for scroll-to targets and diffed list items. */
  id?: string;
  modifiers?: Modifiers;
  /** Component discriminator, e.g. 'vstack', 'text', 'image', 'custom.map'. */
  type: string;
  /** If present and false, the node (and subtree) is not rendered. */
  visibleWhen?: Condition;
}

/**
 * A node in the view tree. The 'type' field is the discriminator. Unknown types beginning with 'custom.' are passed to the host app's component registry; all other unknown types are a validation error.
 */
export type Component = ComponentBase & (StackProps
  | ZStackProps
  | ScrollProps
  | ListProps
  | SpacerProps
  | DividerProps
  | TextProps
  | ImageProps
  | ButtonProps
  | GridProps
  | IconProps
  | TextFieldProps
  | ToggleProps
  | PickerProps
  | ProgressProps
  | ChartProps
  | GradientProps
  | RingsProps
  | SpinnerProps
  | AsyncProps
  | SliderProps
  | RoadmapProps
  | DisclosureProps
  | TickerProps
  | DatePickerProps
  | FileCellProps
  | CalendarProps
  | ClipsProps
  | PagerProps);

/**
 * A paging carousel: shows one child page at a time with page dots and optional auto-advance — the premium rotating-hero-banner pattern. Manual swipe always works; auto-advance pauses under Reduce Motion.
 */
export interface PagerProps {
  /**
   * Auto-advance interval in milliseconds; 0 (default) = manual paging only. 4000–7000 is the premium range.
   */
  autoAdvanceMs?: number;
  /** The pages, one shown at a time. */
  children: Component[];
  /** Page height in points (the carousel doesn't size to content). */
  height?: number;
  /** Page indicator style. */
  indicator?: "dots" | "none";
}

/**
 * A native date picker two-way bound to a $state key holding an ISO yyyy-MM-dd string. Each platform renders its own native calendar from the same contract.
 */
export interface DatePickerProps {
  /** State key holding the selected date (yyyy-MM-dd). */
  bind: string;
  /** Accent tint. */
  color?: Color;
  /** Full month calendar or a compact field. */
  style?: "graphical" | "compact";
}

/**
 * A custom month-grid calendar. The same node does single-day, contiguous range, or multi-day selection via the bindable `mode`. All dates are ISO yyyy-MM-dd strings in $state; range uses two keys, multi uses one comma-separated key. Maps 1:1 to Compose/Aurora (pure layout + state maths).
 */
export interface CalendarProps {
  /** State key for the single-day selection (yyyy-MM-dd). */
  bind?: string;
  /** Accent tint. */
  color?: Color;
  /** Range end state key (yyyy-MM-dd, may be empty). */
  endBind?: string;
  /** 'single' | 'range' | 'multi'. Bindable so chips can switch it live. */
  mode: BindableString;
  /** Multi-select state key: comma-separated yyyy-MM-dd list. */
  multiBind?: string;
  /** Range start state key (yyyy-MM-dd, may be empty). */
  startBind?: string;
  /** 'sunday' (default) or 'monday'. */
  weekStart?: BindableString;
}

/**
 * A full-screen vertical snap-pager — an Instagram Reels / TikTok feed. Swipe up/down to page, double-tap to like. Each page carries its own media, caption and action-rail counts. Maps to a Compose VerticalPager / Aurora scroll-snap container.
 */
export interface ClipsProps {
  /** The feed. Each page is one full-screen clip. */
  pages: ({ audio?: string; author?: string; caption?: string; colors?: Color[]; comments?: string; id?: string; liked?: BindableString; likes?: BindableString; onComment?: Action; onLike?: Action; onMore?: Action; onShare?: Action; shares?: string; })[];
}

/**
 * A document/upload cell: pick a file from the system Files app, then show its format, icon and size. Handles empty / success / error (over max size) states.
 */
export interface FileCellProps {
  /** Accent tint. */
  color?: Color;
  /** Reject files larger than this and show an inline error. */
  maxSizeKB?: number;
  /** Empty-state label (default 'Choose a file'). */
  title?: string;
}

/**
 * An invisible clock that advances a numeric $state value on an interval (a playing progress bar, stopwatch, live counter). Writes through the same two-way binding a slider reads.
 */
export interface TickerProps {
  /** State key it advances. */
  bind: string;
  /** Seconds between ticks (default 1). */
  interval?: number;
  /** Reset to 0 when it reaches max (default false). */
  loop?: boolean;
  /** Upper bound (default 1). */
  max?: number;
  /** Amount added each tick (default 0.01). */
  step?: number;
  /** Bool state key — ticks only while true. */
  while?: string;
}

/**
 * A collapsible section: a tappable header (title, optional subtitle and icon) that reveals or hides its children with a spring. Self-contained — no state binding needed. Its `children` render only while open.
 */
export interface DisclosureProps {
  /** Chevron / icon tint. */
  accent?: Color;
  /** Whether it starts open (default false). */
  expanded?: boolean;
  /** Optional leading SF Symbol name. */
  icon?: string;
  /** Secondary header line. */
  subtitle?: BindableString;
  /** Header label. */
  title: BindableString;
}

/** A numbered vertical roadmap / timeline; steps with a detail expand like sections on tap. */
export interface RoadmapProps {
  /** Node colour. */
  accent?: Color;
  steps: ({ detail?: BindableString; done?: boolean; title: BindableString; })[];
}

/** A draggable continuous control (0…1), two-way bound to screen state. */
export interface SliderProps {
  /** State key it reads and writes (0…1). */
  bind: string;
  color?: Color;
  /** Track thickness in points. */
  height?: number;
  /** Show the draggable thumb (default true). */
  thumb?: boolean;
}

export interface SpinnerProps {
  /** Tint of the indicator. */
  color?: Color;
  /** Size multiplier (1 = default). */
  scale?: number;
}

/**
 * Fetch-then-render container: loads one data source, showing a loading slot while in flight, then the content slot with the response bound as $data.<source.id> (or the error slot on failure).
 */
export interface AsyncProps {
  /** Shown on success; binds to $data.<source.id>. */
  content: Component;
  /** Shown on failure. Defaults to a recoverable message. */
  error?: Component;
  /** Shown while fetching. Defaults to a centred spinner. */
  loading?: Component;
  /** The data source to load. Its id becomes the $data key inside content. */
  source: DataSource;
}

export interface ChartProps {
  /** Series color: hex or '$token.color.*'. */
  color?: string;
  /** Explicit {x,y} samples. */
  points?: ({ x: number; y: number; })[];
  /** Series style. Rendered natively (Swift Charts on iOS). */
  style?: "line" | "area" | "bar";
  /** Y values plotted against their index. Use this OR 'points'. */
  values?: number[];
}

export interface GradientProps {
  /** Two or more stops: hex or '$token.color.*'. */
  colors: string[];
  /** Gradient axis. Defaults to vertical. */
  direction?: "vertical" | "horizontal" | "diagonal";
}

export interface RingsProps {
  /** Color per ring: hex or '$token.color.*'. */
  colors: string[];
  /** Space between rings in points. Default 6. */
  gap?: number;
  /** Ring thickness in points. Default 16. */
  lineWidth?: number;
  /** Progress per ring, 0…1, outermost first (Apple Fitness idiom). */
  values: number[];
}

export interface StackProps {
  /**
   * Cross-axis alignment. Baseline options align text of mixed sizes (e.g. a big number next to a small unit).
   */
  alignment?: "leading" | "center" | "trailing" | "top" | "bottom" | "firstTextBaseline" | "lastTextBaseline";
  children: Component[];
  /**
   * When this stack is the immediate child of a same-axis 'scroll', its rows render lazily (on demand) for smooth scrolling on long content — the default. Set false to force eager rendering (build all rows up front).
   */
  lazy?: boolean;
  /** Gap between children. Token ref like '$token.spacing.md' or a number in points. */
  spacing?: Dimension;
}

export interface ZStackProps {
  alignment?: "topLeading" | "top" | "topTrailing" | "leading" | "center" | "trailing" | "bottomLeading" | "bottom" | "bottomTrailing";
  children: Component[];
}

export interface ScrollProps {
  axis?: "vertical" | "horizontal";
  child: Component;
  /**
   * Apple-Weather-style collapsing hero: 'expanded' fades/shrinks as you scroll over 'range' points while 'compact' pins to the top on a material bar.
   */
  collapsingHeader?: { compact?: Component; expanded: Component; range?: number; };
  /** Fired when the user scrolls near the end — used to drive pagination. */
  onReachEnd?: Action;
  showsIndicators?: boolean;
}

/**
 * Lazy, virtualised list. Either provide static 'children', or bind 'items' to an array and provide an item 'template'.
 */
export interface ListProps {
  children?: Component[];
  /**
   * Rendered instead of any rows when the filtered result is empty — the no-results state (SF Symbol + message + a clear-filters button). Shown live as search/filters narrow to nothing.
   */
  empty?: Component;
  /**
   * Live filtering. A text 'query' over 'fields', an exact 'equals' category match, and a numeric 'min'/'max' range — every value bindable to $state so a search box, chips and range inputs narrow the same list without a round-trip.
   */
  filter?: { equals?: { field?: string; value?: BindableString; }; fields?: string[]; max?: { field?: string; value?: BindableString; }; min?: { field?: string; value?: BindableString; }; query?: BindableString; };
  /**
   * Binding to a data array, e.g. '$data.feed.items'. Each element is exposed as '$item' inside the template.
   */
  items?: BindableString;
  /**
   * Show only the first N rows. A literal number or a $state.<key> binding — pair with pagination to grow the cursor and reveal more.
   */
  limit?: BindableString;
  /**
   * Seconds the shimmer footer lingers before the next page appears, so the load reads as real work rather than an instant jump. Default 0.6.
   */
  loadDelay?: number;
  /**
   * Pagination hook fired when the last row appears. With paginateOnScroll it runs after the shimmer delay; without it, it fires immediately.
   */
  onReachEnd?: Action;
  /**
   * Infinite scroll: reaching the last row auto-loads the next page (shows a shimmer footer, waits 'loadDelay', then fires 'onReachEnd' — or, if none, increments the $state key behind 'limit' by 6). Defaults to true whenever 'limit' binds to $state; set false to keep a manual load-more control.
   */
  paginateOnScroll?: boolean;
  /**
   * When true and 'items' binds to a $state.<key> array, rows can be dragged to reorder; the new order is written back to that state key.
   */
  reorder?: boolean;
  /**
   * A '$state.<key>' the filtered-total (before pagination) is mirrored into, so the contract can show a live count ('128 people') and drive the empty state. Written whenever the count changes.
   */
  resultCount?: string;
  /** Sort the (filtered) items by a field, numeric when both sides parse else lexical. */
  sort?: { by?: BindableString; order?: BindableString; };
  spacing?: Dimension;
  /** Rendered once per element of 'items'. */
  template?: Component;
}

export interface SpacerProps {
  minLength?: Dimension;
}

export interface DividerProps {
  color?: Color;
}

export interface TextProps {
  alignment?: "leading" | "center" | "trailing";
  color?: Color;
  lineLimit?: number;
  /** Typography token ref, e.g. '$token.typography.title2'. */
  style?: BindableString;
  /** Text content. May be literal or a binding like '$data.user.name'. */
  value: BindableString;
}

export interface ImageProps {
  /** Async loading behaviour for remote images. */
  loader?: { aspectRatio?: number; contentMode?: "fit" | "fill"; placeholder?: "skeleton" | "spinner" | "none"; };
  /** Remote URL binding or a bundled asset name prefixed with 'asset:'. */
  source: BindableString;
}

export interface ButtonProps {
  enabledWhen?: Condition;
  /** SF Symbol / shared icon name. */
  icon?: BindableString;
  onTap: Action;
  /** Button style token, e.g. '$token.button.primary'. */
  style?: BindableString;
  title?: BindableString;
}

/** Lazy grid. Provide static 'children', or bind 'items' to an array and supply a 'template'. */
export interface GridProps {
  children?: Component[];
  columns?: number;
  items?: BindableString;
  spacing?: Dimension;
  template?: Component;
}

export interface IconProps {
  color?: Color;
  /** SF Symbol / shared icon name. */
  name: BindableString;
  /** Point size of the symbol. Defaults to the surrounding text size. */
  size?: number;
}

/** Single-line text input, two-way bound to screen state. */
export interface TextFieldProps {
  /** State key to read/write, e.g. 'email' or '$state.email'. */
  bind: string;
  /** Helper / validation text shown below the field; coloured by status. */
  helper?: BindableString;
  /** Leading glyph name (SF Symbol on iOS; mapped per platform). */
  icon?: string;
  /** Which keyboard to present. */
  keyboardType?: "default" | "email" | "number" | "decimal" | "phone" | "url" | "numbersAndPunctuation";
  /** Caption shown above the field. */
  label?: BindableString;
  placeholder?: BindableString;
  /** Mask input (passwords). */
  secure?: boolean;
  /**
   * Explicit visual state. Absent = a normal focus-aware field. 'error'/'success' tint the border, helper and a trailing glyph; 'disabled' dims and blocks editing.
   */
  status?: "error" | "success" | "disabled";
  /** Semantic hint for autofill / suggestions. */
  textContentType?: "email" | "password" | "newPassword" | "name" | "username" | "oneTimeCode" | "telephone";
}

export interface ToggleProps {
  /** Boolean state key to read/write. */
  bind: string;
  title?: BindableString;
}

/**
 * Linear progress. Provide 'value' (0..1, may be a binding) for a determinate bar, or omit for an indeterminate spinner.
 */
export interface ProgressProps {
  color?: Color;
  value?: (number | string);
}

export interface PickerProps {
  /** State key holding the selected option value. */
  bind: string;
  options: ({ label: BindableString; value: string; })[];
  style?: "menu" | "segmented" | "wheel" | "inline";
  title?: BindableString;
}

/**
 * Platform-neutral visual modifiers applied to any component. Renderers translate each key to native equivalents.
 */
export interface Modifiers {
  /**
   * Accessibility metadata. Explicit because a control read as a button by VoiceOver is not automatically labelled for TalkBack.
   */
  accessibility?: { hidden?: boolean; hint?: BindableString; label?: BindableString; role?: "button" | "image" | "header" | "link" | "none"; value?: BindableString; };
  /** Animation applied when this node's inputs change. */
  animation?: { curve?: "linear" | "easeIn" | "easeOut" | "easeInOut" | "spring"; duration?: number; };
  background?: Color;
  /**
   * Gaussian blur radius (points) applied to the node itself — distinct from 'material', which frosts what is behind the node. e.g. a blurred hero image behind a sheet. 0 = no blur.
   */
  blur?: number;
  /** Menu items shown on long-press. */
  contextMenu?: ({ action: Action; icon?: string; role?: "default" | "destructive"; title: BindableString; })[];
  cornerRadius?: Dimension;
  frame?: { height?: Dimension; maxWidth?: (Dimension | "infinity"); width?: Dimension; };
  /** Extra invisible tap padding (points) so small controls stay comfortably tappable. */
  hitSlop?: number;
  /** Extend this node under the safe area (edge-to-edge) — for immersive backgrounds. */
  ignoresSafeArea?: boolean;
  /**
   * Translucent system material behind the node. 'ultraThin'…'thick' are the four native blur tiers, 'bar' matches the toolbar material, and 'glass' is the visionOS-style frosted pane (material + hairline gradient stroke). Renders natively on iOS/Android/Aurora.
   */
  material?: "ultraThin" | "thin" | "regular" | "thick" | "bar" | "glass";
  /** Double-tap gesture on the whole component (e.g. like-to-favourite). */
  onDoubleTap?: Action;
  /** Long-press gesture; commonly opens a context menu. */
  onLongPress?: Action;
  /** Tap gesture on the whole component. */
  onTap?: Action;
  opacity?: number;
  padding?: EdgeInsets;
  /** How a 'presentWhen' subtree is presented. */
  presentStyle?: "fullScreen" | "sheet";
  /**
   * Present this subtree as a modal when the given bool $state key is true. It shares the screen's state, so a filter sheet drives the same list.
   */
  presentWhen?: string;
  /**
   * A rhythmic auto-reversing scale 'heartbeat' — a bool $state key (pulses while true) or an object { while, scale, interval }. e.g. album art beating to music, or a live dot.
   */
  pulse?: (string | { interval?: number; scale?: number; while?: string; });
  /**
   * Rotation in degrees — a constant or a $state binding. Pairs with 'animation' for a spinning / flipping element.
   */
  rotation?: (number | string);
  /**
   * Uniform scale — a number or a $state binding. Pair with animation for a spring scale on state change.
   */
  scale?: (number | string);
  shadow?: { color?: Color; radius?: Dimension; x?: number; y?: number; };
  /**
   * Explicit, platform-neutral sizing per axis. Prefer this over 'frame' — it lays out identically on iOS and Android instead of relying on platform defaults.
   */
  size?: { height?: AxisSize; width?: AxisSize; };
  /**
   * Swipe-to-reveal actions. 'leading' reveals on a left-to-right swipe, 'trailing' on a right-to-left swipe.
   */
  swipe?: { actionWidth?: number; fullSwipe?: boolean; leading?: SwipeAction[]; style?: "native" | "custom"; trailing?: SwipeAction[]; };
  /**
   * Make the element interactively pinch-to-zoom, two-finger-rotate and drag, double-tap to reset — a photo-viewer gesture from one flag.
   */
  zoomable?: boolean;
}

/**
 * Declarative networking. Sources are fetched by the runtime and exposed under '$data.<id>'. Execution mode controls parallelism so both platforms behave identically.
 */
export interface DataConfig {
  /**
   * 'parallel' fetches all sources concurrently (async let / TaskGroup on iOS, coroutine async on Android). 'sequential' awaits them in order — use when one request depends on another.
   */
  mode?: "parallel" | "sequential";
  sources: DataSource[];
}

/**
 * A single network request described declaratively. The host app maps 'service' to a base URL / auth, so payloads never hardcode hostnames.
 */
export interface DataSource {
  /** Request body for write methods. Object values may contain bindings. */
  body?: unknown;
  /** IDs that must resolve first; forces ordering even in parallel mode. */
  dependsOn?: string[];
  headers?: { [key: string]: BindableString; };
  /** Referenced as '$data.<id>'. */
  id: string;
  method?: "GET" | "POST" | "PUT" | "PATCH" | "DELETE";
  /** Path template; '{param}' segments are filled from 'params' or bindings. */
  path: BindableString;
  /** Caching strategy. */
  policy?: "networkOnly" | "cacheFirst" | "cacheThenNetwork";
  /** Query items; values may be bindings. */
  query?: { [key: string]: BindableString; };
  /** Logical service name resolved by the host to a base URL + auth, e.g. 'catalog'. */
  service: string;
}

interface ActionBase {
  /**
   * Action kind. Kept in lockstep with the engines' ActionInterpreter — every kind here is one a client accepts. See spec/docs/authoring.md for each kind's field set.
   */
  action: "navigate" | "dismiss" | "dismissRoot" | "openURL" | "openDeepLink" | "setState" | "increment" | "refresh" | "request" | "sequence" | "parallel" | "condition" | "delay" | "showToast" | "scrollTo" | "haptic" | "share" | "saveFile" | "preview" | "log" | "analytics" | "requireVersion" | "requestPermission" | "custom";
  /** Optional analytics event emitted when this action fires. */
  analytics?: AnalyticsTag;
}

/**
 * A declarative action triggered by an event. Actions compose: 'sequence' and 'parallel' wrap child actions. This is a closed vocabulary so both platforms interpret it identically.
 */
export type Action = ActionBase & ({ params?: { [key: string]: BindableString; }; sheet?: SheetConfig; to: string; transition?: "push" | "sheet" | "fullScreenCover" | "replace"; }
  | { url: BindableString; }
  | { key: string; value?: unknown; }
  | { onError?: Action; onSuccess?: Action; source: DataSource; }
  | { actions: Action[]; }
  | { else?: Action; if: Condition; then: Action; }
  | { message: BindableString; style?: "info" | "success" | "error"; }
  | { style?: "light" | "medium" | "heavy" | "success" | "warning" | "error"; }
  | { text?: BindableString; url?: BindableString; }
  | { name: string; payload?: unknown; });

/**
 * How a 'navigate transition:sheet' presents its modal. Additive to 'navigate'; each renderer maps 'detents' to its native sheet (iOS presentationDetents, Android material3 ModalBottomSheet, Aurora bottom Drawer). Omitted fields fall back to platform defaults.
 */
export interface SheetConfig {
  /** Top corner radius of the sheet; platform default when omitted. */
  cornerRadius?: Dimension;
  /**
   * Allowed resting heights, in order. A named tier, a fixed 'height' in points, or a 'fraction' of the screen. A single value pins the sheet; multiple values let the user drag between them.
   */
  detents?: ("small" | "medium" | "large" | { height: number; } | { fraction: number; })[];
  /** Allow tap-outside / swipe-down to dismiss. false forces an explicit in-content close action. */
  dismissible?: boolean;
  /** Show the grabber / drag handle at the top of the sheet. */
  dragIndicator?: boolean;
}

/** Boolean expression over bindings. Exactly one operator key is expected. */
export interface Condition {
  and?: Condition[];
  equals?: BindableString[];
  exists?: BindableString;
  not?: Condition;
  notEquals?: BindableString[];
  or?: Condition[];
}

export interface AnalyticsTag {
  event?: string;
  params?: { [key: string]: BindableString; };
  screenName?: string;
}

/**
 * A string that is either a literal, or a binding expression starting with '$'. Namespaces: $data.<source>.<path>, $token.<group>.<name>, $env.<key> (locale, theme, platform...), $state.<key>, $params.<key> (navigation parameters passed to this screen), $item.<path> (inside list templates). Interpolation is allowed: 'Hello, $data.user.name'.
 */
export type BindableString = string;

/**
 * Sizing along one axis. 'fixed' = exact points (needs 'value'); 'hug' = size to content; 'fill' = take all available space; 'weight' = share available space proportionally (needs 'value').
 */
export interface AxisSize {
  max?: number;
  min?: number;
  mode: "fixed" | "hug" | "fill" | "weight";
  value?: number;
}

export interface SwipeAction {
  action: Action;
  /** SF Symbol / shared icon name. */
  icon?: string;
  role?: "default" | "destructive";
  /** Button colour; defaults by role (destructive = red). */
  tint?: Color;
  title?: BindableString;
}

/** A length in points (number) or a spacing/size token ref (string like '$token.spacing.md'). */
export type Dimension = (number | string);

/** A design token ref ('$token.color.primary'), a hex string ('#RRGGBB' / '#RRGGBBAA'), or a binding. */
export type Color = string;

/** Either a single value applied to all edges, or per-edge values. */
export type EdgeInsets = (Dimension | { bottom?: Dimension; horizontal?: Dimension; leading?: Dimension; top?: Dimension; trailing?: Dimension; vertical?: Dimension; });

/** The root SDUI payload: a contract version plus exactly one screen. */
export interface SDUIDocument {
  version: string;
  screen: Screen;
}
