// Chat view — DOM port of PromptView / ChatBubble / TypingDotsView from
// IslandViewContent.swift.

import { h, svg, clear } from "./dom";
import { ICONS } from "./icons";
import { Bridge, type ChatContext } from "../core/bridge";
import { Sound } from "../core/sound";
import { State, type ChatMessage } from "../core/state";
import type { ViewHost } from "./views";

let nextId = 1;

function bubble(message: ChatMessage): HTMLElement {
  if (message.role === "user") {
    return h(
      "div",
      { class: "chat-row user" },
      h("div", { class: "bubble", text: message.content }),
    );
  }
  return h("div", { class: "chat-row" }, h("div", { class: "reply", text: message.content }));
}

function typingDots(): HTMLElement {
  return h(
    "div",
    { class: "chat-row" },
    h("div", { class: "typing" }, h("i"), h("i"), h("i")),
  );
}

/** The coloured chip showing what the question is about (a dropped file). */
function contextChip(label: string): HTMLElement {
  const chip = h("div", { class: "chip" }, h("i", { class: "chip-dot" }), h("span", { text: label }));
  requestAnimationFrame(() => chip.classList.add("settled"));
  return chip;
}

export function buildPrompt(onHeightChange: () => void): ViewHost {
  const chipRow = h("div", { class: "chip-row" });
  const log = h("div", { class: "chat-log" });
  const input = h("input", {
    type: "text",
    class: "chat-input",
    placeholder: "Ask me anything…",
    spellcheck: "false",
  }) as HTMLInputElement;
  const send = h("button", { class: "send-btn", title: "Send" }, svg(ICONS.arrowUp, 11));
  const stop = h("button", { class: "send-btn", title: "Stop", text: "■" });
  stop.style.display = "none";
  stop.addEventListener("click", () => void Bridge.chatCancel());
  const provider = h("select", { title: "Chat provider", style: "max-width:135px;font-size:11px;margin-bottom:6px" }) as HTMLSelectElement;
  for (const [value, label] of [["claudeCLI", "Claude Code"], ["codexCLI", "Codex"], ["anthropic", "Anthropic API"]]) {
    provider.append(h("option", { value, text: label }));
  }
  provider.value = State.settings.chatProvider;
  provider.addEventListener("change", async () => {
    const previous = State.settings.chatProvider;
    provider.disabled = true;
    try {
      const next = { ...State.settings, chatProvider: provider.value as typeof State.settings.chatProvider };
      await Bridge.saveChatSettings(next);
      State.settings = next;
      await Bridge.chatReset();
      State.chatHistory = [];
      State.notify();
    } catch {
      provider.value = previous;
    } finally { provider.disabled = false; }
  });
  const fresh = h("button", { text: "New chat", style: "font-size:11px;margin-left:8px" });
  fresh.addEventListener("click", async () => {
    if (sending) return;
    await Bridge.chatReset();
    State.chatHistory = [];
    State.droppedFile = null;
    State.notify();
  });
  const options = h("div", {}, provider, fresh);
  const bar = h("div", { class: "chat-bar" }, input, send, stop);

  const el = h(
    "div",
    { class: "view" },
    h("div", { class: "card wash chat-card" }, h("div", { class: "chat-body" }, chipRow, log, options, bar)),
  );
  (el.querySelector(".card") as HTMLElement).style.setProperty("--wash", "rgba(99,102,241,0.5)");

  let sending = false;
  let renderedCount = -1;

  async function submit() {
    const query = input.value.trim();
    if (!query || sending) return;
    input.value = "";
    sending = true;
    Sound.play("send");

    State.chatHistory.push({ id: nextId++, role: "user", content: query });
    State.stateOverride = "thinking";
    State.notify();
    onHeightChange();

    const file = State.droppedFile;
    const context: ChatContext | null =
      State.chatHistory.length === 1 && file ? { kind: "file", name: file.name, path: file.path } : null;

    try {
      const reply = await Bridge.chatSend(query, context);
      State.chatHistory.push({ id: nextId++, role: "assistant", content: reply.text });
      State.stateOverride = null;
      Sound.play("finish");
    } catch (err) {
      State.stateOverride = null;
      const message = String(err).replace(/^Error:\s*/, "");
      if (message !== "Chat stopped.") {
        State.noteMessage = message;
        State.view = "note";
        Sound.play("error");
      }
    } finally {
      sending = false;
      State.notify();
      onHeightChange();
      input.focus();
    }
  }

  send.addEventListener("click", () => void submit());
  input.addEventListener("keydown", (e) => {
    if ((e as KeyboardEvent).key === "Enter") {
      e.preventDefault();
      void submit();
    }
    e.stopPropagation(); // Escape closes the island, not the chat
  });

  return {
    el,
    sync() {
      const file = State.droppedFile;
      const wantChip = file?.name ?? "";
      if (chipRow.dataset.label !== wantChip) {
        chipRow.dataset.label = wantChip;
        clear(chipRow);
        if (wantChip) chipRow.append(contextChip(wantChip));
      }

      const thinking = State.stateOverride === "thinking";
      const count = State.chatHistory.length + (thinking ? 0.5 : 0);
      if (count !== renderedCount) {
        renderedCount = count;
        clear(log);
        for (const m of State.chatHistory) log.append(bubble(m));
        if (thinking) log.append(typingDots());
        log.scrollTop = log.scrollHeight;
      }

      input.placeholder = State.chatHistory.length === 0 ? "Ask me anything…" : "Continue…";
      input.disabled = sending;
      send.disabled = sending;
      provider.disabled = sending;
      fresh.disabled = sending;
      provider.value = State.settings.chatProvider;
      stop.style.display = sending && State.settings.chatProvider !== "anthropic" ? "" : "none";
    },
    focus() {
      input.focus();
      input.select();
    },
  };
}
