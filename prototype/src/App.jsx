import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import {
  ArrowClockwise,
  ArrowLeft,
  ArrowUUpLeft,
  Check,
  CheckCircle,
  ClockCounterClockwise,
  Gear,
  ShieldCheck,
  Trash,
  X,
} from "@phosphor-icons/react";
import { useMemo, useState } from "react";

const candidates = [
  { id: 1, app: "ChatGPT", name: "可重新生成的响应缓存", size: "860 MB", recommended: true },
  { id: 2, app: "Claude", name: "更新与网页资源缓存", size: "520 MB", recommended: true },
  { id: 3, app: "Cursor", name: "扩展下载缓存", size: "410 MB", recommended: true },
  { id: 4, app: "豆包", name: "缩略图与临时预览", size: "286 MB", recommended: true },
  { id: 5, app: "ChatGPT", name: "诊断日志", size: "196 MB", recommended: true },
  { id: 6, app: "Claude", name: "旧版本安装包", size: "128 MB", recommended: true },
];

const spring = { type: "spring", stiffness: 420, damping: 36, mass: 0.8 };

function Logo({ size = 38, className = "" }) {
  return (
    <img
      className={`crab-logo ${className}`}
      src="/assets/crab-protective-orbit.png"
      width={size}
      height={size}
      alt="Crab"
    />
  );
}

function Modal({ children, onClose, label }) {
  const reduceMotion = useReducedMotion();
  return (
    <motion.div
      className="modal-backdrop"
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      transition={{ duration: reduceMotion ? 0 : 0.16 }}
      onMouseDown={(event) => event.target === event.currentTarget && onClose?.()}
    >
      <motion.section
        className="modal-card"
        role="dialog"
        aria-modal="true"
        aria-label={label}
        initial={reduceMotion ? false : { opacity: 0, scale: 0.96, y: 10 }}
        animate={{ opacity: 1, scale: 1, y: 0 }}
        exit={reduceMotion ? { opacity: 0 } : { opacity: 0, scale: 0.97, y: 6 }}
        transition={spring}
      >
        {children}
      </motion.section>
    </motion.div>
  );
}

function WindowHeader({ onBrand, onHistory }) {
  return (
    <header className="window-header">
      <div className="traffic-lights" aria-hidden="true">
        <span className="red" />
        <span className="yellow" />
        <span className="green" />
      </div>
      <button className="brand-button" onClick={onBrand} aria-label="打开 Crab 快捷面板">
        <Logo size={29} />
        <span>Crab</span>
      </button>
      <button className="icon-button history-button" onClick={onHistory} aria-label="查看历史">
        <ClockCounterClockwise size={22} weight="regular" />
      </button>
    </header>
  );
}

function Home({ onReview, onScan }) {
  const [scanning, setScanning] = useState(false);

  function rescan() {
    if (scanning) return;
    setScanning(true);
    window.setTimeout(() => setScanning(false), 900);
    onScan?.();
  }

  return (
    <motion.section className="home-screen" initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ duration: 0.2 }}>
      <div className="result-stack">
        <Logo size={322} className="hero-logo" />
        <div className="result-copy">
          <div className="storage-number"><strong>2.4</strong><span>GB</span></div>
          <div className="safe-label">可安全审阅</div>
        </div>
      </div>
      <p className="protection-copy">聊天、项目和生成文件均受保护</p>
      <div className="home-actions">
        <button className="primary-button" onClick={onReview}>查看项目</button>
        <button className="link-button" onClick={rescan} disabled={scanning}>
          <ArrowClockwise className={scanning ? "spin" : ""} size={17} weight="bold" />
          {scanning ? "正在扫描" : "重新扫描"}
        </button>
      </div>
      <p className="safety-footer">不会自动选择 · 只移入废纸篓</p>
    </motion.section>
  );
}

function Review({ selected, setSelected, onBack, onContinue }) {
  const selectedCount = selected.size;
  const allRecommendedSelected = candidates.filter((item) => item.recommended).every((item) => selected.has(item.id));

  function toggle(id) {
    setSelected((current) => {
      const next = new Set(current);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  }

  function selectRecommended() {
    setSelected(allRecommendedSelected ? new Set() : new Set(candidates.filter((item) => item.recommended).map((item) => item.id)));
  }

  return (
    <motion.section className="review-screen" initial={{ opacity: 0, x: 18 }} animate={{ opacity: 1, x: 0 }} exit={{ opacity: 0, x: 12 }} transition={spring}>
      <div className="review-topbar">
        <button className="back-button" onClick={onBack}><ArrowLeft size={18} weight="bold" />返回</button>
        <div className="review-heading">
          <h1>审阅项目</h1>
          <p>默认不选择任何内容</p>
        </div>
        <button className="recommend-button" onClick={selectRecommended}>{allRecommendedSelected ? "取消全选" : "选择推荐项"}</button>
      </div>

      <div className="candidate-list" role="list" aria-label="可清理项目">
        {candidates.map((item) => {
          const checked = selected.has(item.id);
          return (
            <button
              className={`candidate-row ${checked ? "selected" : ""}`}
              key={item.id}
              onClick={() => toggle(item.id)}
              role="checkbox"
              aria-checked={checked}
            >
              <span className="checkbox" aria-hidden="true">{checked && <Check size={15} weight="bold" />}</span>
              <span className="candidate-copy"><strong>{item.app}</strong><small>{item.name}</small></span>
              <span className="candidate-size">{item.size}</span>
            </button>
          );
        })}
      </div>

      <div className="review-footer">
        <div className="protected-note"><ShieldCheck size={20} weight="fill" /><span><strong>受保护内容不会出现在这里</strong><small>聊天、项目与用户生成文件已排除</small></span></div>
        <button className="primary-button compact" disabled={!selectedCount} onClick={onContinue}>
          {selectedCount ? `加入计划（${selectedCount}）` : "加入计划"}
        </button>
      </div>
    </motion.section>
  );
}

function QuickPanel({ onClose, onReview, onHistory, onSettings }) {
  const reduceMotion = useReducedMotion();
  return (
    <motion.aside
      className="quick-panel"
      initial={reduceMotion ? false : { opacity: 0, scale: 0.96, y: -8 }}
      animate={{ opacity: 1, scale: 1, y: 0 }}
      exit={reduceMotion ? { opacity: 0 } : { opacity: 0, scale: 0.97, y: -4 }}
      transition={spring}
      aria-label="Crab 快捷面板"
    >
      <div className="panel-notch" aria-hidden="true" />
      <button className="panel-close" onClick={onClose} aria-label="关闭"><X size={16} /></button>
      <Logo size={92} className="panel-logo" />
      <div className="panel-number"><strong>2.4</strong><span>GB</span></div>
      <h2>可安全审阅</h2>
      <p className="panel-tools">来自 5 个 AI 工具</p>
      <button className="primary-button panel-primary" onClick={onReview}>查看项目</button>
      <p className="panel-safe"><ShieldCheck size={18} weight="fill" />聊天、项目和生成文件受保护</p>
      <div className="panel-footer">
        <button onClick={onHistory}><ClockCounterClockwise size={18} />历史</button>
        <span aria-hidden="true">·</span>
        <button onClick={onSettings}><Gear size={18} />设置</button>
      </div>
    </motion.aside>
  );
}

function ConfirmDialog({ count, onCancel, onConfirm }) {
  return (
    <Modal onClose={onCancel} label="确认移入废纸篓">
      <div className="modal-icon trash"><Trash size={27} weight="fill" /></div>
      <h2>移入废纸篓？</h2>
      <p>将 {count} 个可重新生成的项目移入废纸篓。</p>
      <div className="modal-safety"><ShieldCheck size={20} weight="fill" /><span><strong>你的内容保持原样</strong><small>聊天、项目和生成文件不会被移动</small></span></div>
      <div className="modal-actions">
        <button className="secondary-button" onClick={onCancel}>取消</button>
        <button className="danger-button" onClick={onConfirm}>移入废纸篓</button>
      </div>
    </Modal>
  );
}

function SuccessDialog({ count, onUndo, onDone }) {
  return (
    <Modal onClose={onDone} label="清理完成">
      <div className="modal-icon success"><CheckCircle size={31} weight="fill" /></div>
      <h2>已移入废纸篓</h2>
      <p>{count} 个项目仍可从废纸篓恢复。</p>
      <div className="modal-actions">
        <button className="secondary-button with-icon" onClick={onUndo}><ArrowUUpLeft size={17} weight="bold" />撤销</button>
        <button className="primary-button modal-primary" onClick={onDone}>完成</button>
      </div>
    </Modal>
  );
}

function HistoryDialog({ receipt, onClose }) {
  return (
    <Modal onClose={onClose} label="历史记录">
      <button className="modal-close" onClick={onClose} aria-label="关闭"><X size={17} /></button>
      <div className="modal-icon neutral"><ClockCounterClockwise size={28} /></div>
      <h2>历史</h2>
      {receipt ? (
        <div className="receipt"><CheckCircle size={22} weight="fill" /><span><strong>已移入废纸篓 {receipt.count} 项</strong><small>刚刚 · 可从废纸篓恢复</small></span></div>
      ) : (
        <div className="empty-history"><p>还没有清理记录</p><small>Crab 会在这里保存每次操作的收据</small></div>
      )}
    </Modal>
  );
}

function SettingsDialog({ onClose }) {
  return (
    <Modal onClose={onClose} label="设置">
      <button className="modal-close" onClick={onClose} aria-label="关闭"><X size={17} /></button>
      <div className="modal-icon neutral"><Gear size={28} /></div>
      <h2>设置</h2>
      <div className="settings-row"><span><strong>清理方式</strong><small>始终移入废纸篓</small></span><span className="locked-pill">已锁定</span></div>
      <p className="settings-help">Crab 不提供永久删除选项。</p>
    </Modal>
  );
}

export function App() {
  const [screen, setScreen] = useState("home");
  const [selected, setSelected] = useState(new Set());
  const [overlay, setOverlay] = useState(null);
  const [receipt, setReceipt] = useState(null);
  const selectedCount = selected.size;
  const selectedSize = useMemo(() => candidates.filter((item) => selected.has(item.id)).map((item) => item.size), [selected]);

  function finishClean() {
    setReceipt({ count: selectedCount, sizes: selectedSize, at: Date.now() });
    setOverlay("success");
  }

  function undoClean() {
    setReceipt(null);
    setOverlay(null);
  }

  function done() {
    setOverlay(null);
    setSelected(new Set());
    setScreen("home");
  }

  return (
    <main className="desktop-stage">
      <section className="app-window" aria-label="Crab Mac 应用原型">
        <WindowHeader onBrand={() => setOverlay("panel")} onHistory={() => setOverlay("history")} />
        <AnimatePresence mode="wait" initial={false}>
          {screen === "home" ? (
            <Home key="home" onReview={() => setScreen("review")} />
          ) : (
            <Review key="review" selected={selected} setSelected={setSelected} onBack={() => setScreen("home")} onContinue={() => setOverlay("confirm")} />
          )}
        </AnimatePresence>

        <AnimatePresence>
          {overlay === "panel" && (
            <QuickPanel
              onClose={() => setOverlay(null)}
              onReview={() => { setOverlay(null); setScreen("review"); }}
              onHistory={() => setOverlay("history")}
              onSettings={() => setOverlay("settings")}
            />
          )}
          {overlay === "confirm" && <ConfirmDialog count={selectedCount} onCancel={() => setOverlay(null)} onConfirm={finishClean} />}
          {overlay === "success" && <SuccessDialog count={receipt?.count ?? selectedCount} onUndo={undoClean} onDone={done} />}
          {overlay === "history" && <HistoryDialog receipt={receipt} onClose={() => setOverlay(null)} />}
          {overlay === "settings" && <SettingsDialog onClose={() => setOverlay(null)} />}
        </AnimatePresence>
      </section>
    </main>
  );
}
