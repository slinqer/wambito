// Automatic capture's "¿Cómo funciona?" (spec sections 4 and 5): the five steps in a sheet, one
// page each, swiped or moved with Siguiente and the dots. The web's twin is
// apps/web/app/features/capture/CaptureSteps.tsx (capture.css `.lk-capture-step`).
//
// It is also the prominent disclosure before notification access: on the first switch on the last
// step repeats what is read and that the text stays on the phone, right above "Activar acceso".
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../l10n/app_localizations.dart';
import '../theme/surfaces.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.g.dart';
import '../ui/css_text.dart';
import '../ui/lk_theme.dart';
import '../ui/press_button.dart';
import '../ui/sheet.dart';
import 'capture_demos.dart';

/// The five steps, in order (the web's `CAPTURE_STEPS`).
enum CaptureHowStep { pay, reads, decide, learns, next }

/// Opens the steps. With [askAccess] (the first switch on) the last step ends with "Activar
/// acceso" and the answer is true when the person goes on; otherwise it ends with "Entendido".
/// Closing the sheet answers false.
///
/// The pages scroll with the sheet; the dots and the button (and, on the last step, the disclosure
/// right above it) stay at the sheet's bottom, always in view.
Future<bool> showHowCaptureWorks(BuildContext context, {required bool askAccess}) async {
  final l10n = AppLocalizations.of(context);
  final go = await LkSheet.show<bool>(
    context,
    title: askAccess ? l10n.autoCaptureTitle : l10n.autoCaptureHowLink,
    wrap: (sheet) => HowCaptureWorks(askAccess: askAccess, child: sheet),
    children: const [_HowPages()],
    stuck: const [_HowFooter()],
  );
  return go ?? false;
}

/// Holds the steps' state (the page in view) for the sheet it wraps: the pages in its body and the
/// dots and button in its stuck footer.
class HowCaptureWorks extends StatefulWidget {
  const HowCaptureWorks({super.key, required this.askAccess, required this.child});

  /// The last step asks for notification access ("Activar acceso") instead of "Entendido".
  final bool askAccess;

  /// The sheet.
  final Widget child;

  @override
  State<HowCaptureWorks> createState() => _HowCaptureWorksState();
}

class _HowCaptureWorksState extends State<HowCaptureWorks> {
  final _controller = PageController();
  int _page = 0;

  /// The steps went compact because the tall ones did not fit the sheet (see [_HowPages]).
  bool _tooTall = false;

  static final _last = CaptureHowStep.values.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _go(int page) {
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.jumpToPage(page);
    } else {
      _controller.animateToPage(
        page,
        duration: WambitoTokens.durationSheet,
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _turned(int page) => setState(() => _page = page);

  void _overflowed() {
    if (!_tooTall && mounted) setState(() => _tooTall = true);
  }

  @override
  Widget build(BuildContext context) =>
      _HowScope(state: this, page: _page, tooTall: _tooTall, child: widget.child);
}

/// The steps' state, for the parts of the sheet.
class _HowScope extends InheritedWidget {
  const _HowScope({
    required this.state,
    required this.page,
    required this.tooTall,
    required super.child,
  });

  final _HowCaptureWorksState state;

  /// The page in view.
  final int page;

  /// The tall steps did not fit: the compact ones are shown.
  final bool tooTall;

  static _HowCaptureWorksState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_HowScope>()!.state;

  @override
  bool updateShouldNotify(_HowScope old) => old.page != page || old.tooTall != tooTall;
}

/// The pages, one step each, swiped sideways. Every step is as tall as the tallest one (the hidden
/// copies under the page view give the height), so the sheet keeps its size from step to step.
///
/// A short screen gets the compact steps at once. On a taller one the tall steps are tried first;
/// if the sheet then has to scroll (a large font or display size, or the room the footer keeps for
/// the disclosure), the steps go compact, so the demo is never cut under the footer.
class _HowPages extends StatelessWidget {
  const _HowPages();

  @override
  Widget build(BuildContext context) {
    final how = _HowScope.of(context);
    final tooTall = context.dependOnInheritedWidgetOfExactType<_HowScope>()!.tooTall;
    final compact = tooTall || MediaQuery.sizeOf(context).height < CaptureHowStepView.compactBelow;
    if (!compact) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final position = Scrollable.maybeOf(context)?.position;
        if (position != null && position.hasContentDimensions && position.maxScrollExtent > 0) {
          how._overflowed();
        }
      });
    }
    return Padding(
      padding: EdgeInsets.only(top: compact ? WambitoTokens.space1 : WambitoTokens.space3),
      child: _Tallest(
        children: [
          for (final step in CaptureHowStep.values)
            CaptureHowStepView(step: step, compact: compact),
          PageView.builder(
            controller: how._controller,
            itemCount: CaptureHowStep.values.length,
            onPageChanged: how._turned,
            itemBuilder: (context, page) => Align(
              alignment: Alignment.topCenter,
              child: CaptureHowStepView(step: CaptureHowStep.values[page], compact: compact),
            ),
          ),
        ],
      ),
    );
  }
}

/// The sheet's stuck footer: the dots, then Siguiente; on the last step the disclosure and the
/// button that ends ("Activar acceso" or "Entendido").
class _HowFooter extends StatelessWidget {
  const _HowFooter();

  @override
  Widget build(BuildContext context) {
    final how = _HowScope.of(context);
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final page = how._page;
    final last = page == _HowCaptureWorksState._last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space2,
      children: [
        _Dots(count: CaptureHowStep.values.length, current: page, onTap: how._go),
        // The disclosure's room is kept on every step (shown on the last one only), so the sheet
        // does not grow when it appears.
        Visibility(
          visible: last,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: CssParagraph(
            l10n.autoCaptureHowDisclosure,
            key: last ? const Key('autoCapture.how.disclosure') : null,
            // Three lines, what is read and what leaves the phone: the label's size keeps them
            // within the room a short phone has under the steps.
            style: LkText.label.copyWith(color: colors.ink),
          ),
        ),
        if (!last)
          PressButton.text(
            l10n.autoCaptureHowNext,
            key: const Key('autoCapture.how.next'),
            onPressed: () => how._go(page + 1),
          )
        else ...[
          if (how.widget.askAccess)
            PressButton.text(
              l10n.autoCaptureExplainerConfirm,
              key: const Key('autoCapture.explainer.confirm'),
              onPressed: () => Navigator.of(context).pop(true),
            )
          else
            PressButton.text(
              l10n.autoCaptureHowDone,
              key: const Key('autoCapture.how.done'),
              onPressed: () => Navigator.of(context).pop(false),
            ),
        ],
      ],
    );
  }
}

/// One step: its scene (decoration), title, body and, for most, its demo.
class CaptureHowStepView extends StatelessWidget {
  const CaptureHowStepView({super.key, required this.step, this.compact});

  final CaptureHowStep step;

  /// The compact step (a smaller scene beside the words); null decides by [compactBelow].
  final bool? compact;

  /// Screens shorter than this (logical pixels) get the compact step: a smaller scene beside the
  /// words. The parity goldens (915 tall) and most phones keep the scene above.
  static const compactBelow = 820.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.lkColors;
    final (title, body) = switch (step) {
      CaptureHowStep.pay => (l10n.autoCaptureHowPayTitle, l10n.autoCaptureHowPayBody),
      CaptureHowStep.reads => (l10n.autoCaptureHowReadsTitle, l10n.autoCaptureHowReadsBody),
      CaptureHowStep.decide => (l10n.autoCaptureHowDecideTitle, l10n.autoCaptureHowDecideBody),
      CaptureHowStep.learns => (l10n.autoCaptureHowLearnsTitle, l10n.autoCaptureHowLearnsBody),
      CaptureHowStep.next => (l10n.autoCaptureHowNextTitle, l10n.autoCaptureHowNextBody),
    };
    final demo = switch (step) {
      CaptureHowStep.pay => const MainPicture(),
      CaptureHowStep.reads => const ChipsDemo(),
      CaptureHowStep.decide => const NoticeDemo(),
      CaptureHowStep.learns => const LearnDemo(),
      CaptureHowStep.next => null,
    };
    // On a short screen the scene shrinks and sits beside the words, so a step (demo included)
    // fits in the sheet without scrolling; on a tall one it stands above them, as on the web.
    final compact = this.compact ?? MediaQuery.sizeOf(context).height < compactBelow;
    final scene = Image.asset(
      'assets/wambi/capture-step${step.index + 1}.webp',
      width: compact ? 72 : 200,
      height: compact ? 72 : 200,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
    );
    final words = [
      Semantics(
        header: true,
        child: Text(
          title,
          style: LkText.title.copyWith(fontSize: compact ? 20 : 22, height: 1.2, color: colors.ink),
        ),
      ),
      Text(body, style: LkText.body.copyWith(height: 1.45, color: colors.inkMuted)),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: WambitoTokens.space2,
      children: [
        if (compact)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: WambitoTokens.space3,
            children: [
              scene,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: WambitoTokens.space1,
                  children: words,
                ),
              ),
            ],
          )
        else ...[
          Center(child: scene),
          ...words,
        ],
        ?demo,
      ],
    );
  }
}

/// Sizes to the tallest of its children but the last, which it lays out at that height and is the
/// only one painted, hit or read: the others only measure. Its element shows finders only the last
/// child too, so a test finds each step's text once.
class _Tallest extends MultiChildRenderObjectWidget {
  const _Tallest({required super.children});

  @override
  MultiChildRenderObjectElement createElement() => _TallestElement(this);

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTallest();
}

class _TallestElement extends MultiChildRenderObjectElement {
  _TallestElement(super.widget);

  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    if (children.isNotEmpty) visitor(children.last);
  }
}

class _TallestParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderTallest extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TallestParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TallestParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TallestParentData) child.parentData = _TallestParentData();
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    var height = 0.0;
    var child = firstChild;
    while (child != null && child != lastChild) {
      child.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
      if (child.size.height > height) height = child.size.height;
      child = childAfter(child);
    }
    size = constraints.constrain(Size(width, height));
    lastChild?.layout(BoxConstraints.tight(size));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final shown = lastChild;
    if (shown != null) context.paintChild(shown, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      lastChild?.hitTest(result, position: position) ?? false;

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    final shown = lastChild;
    if (shown != null) visitor(shown);
  }
}

/// The dots under the pages: the step in view is a wider pill in the brand's color; each dot is a
/// 44px target that goes to its step.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.current, required this.onTap});

  final int count;
  final int current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.lkColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Semantics(
            key: Key('autoCapture.how.dot.$i'),
            button: true,
            selected: i == current,
            label: AppLocalizations.of(context).autoCaptureHowStepOf(i + 1, count),
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onTap(i),
              child: SizedBox(
                width: 32,
                height: 44,
                child: Center(
                  child: Container(
                    width: i == current ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == current ? colors.brand : colors.stroke,
                      borderRadius: LkSurface.radius(LkRadius.pill),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
