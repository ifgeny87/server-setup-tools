# Бойлерплейт плана с тикетами

Шаблон одной страницы плана. Предметных задач здесь нет. Агент создаёт один файл `docs/todo-plan.html` по каркасу ниже. Стили лежат в `<style>` в `head`, логика — в `<script>` перед `</body>`. Отдельные `style.css` и `plan.js` не создавать. CSS и JS из каркаса копировать дословно, менять только тексты тикетов и подстановки.

Язык страниц — язык пользователя. Код продукта агент не меняет, пока об этом нет отдельной просьбы.

## Какой файл создавать

```text
docs/todo-plan.html
```

`PREFIX` — короткий код проекта латиницей, 2–5 букв. Номер — три цифры по порядку выполнения: `PREFIX-001`. У эпика подпункты `PREFIX-001-1` внутри того же блока, отдельные страницы для подпунктов не создавать.

Все тикеты лежат в `todo-plan.html`. Описание каждого свёрнуто: `details` без атрибута `open`. Ссылки между тикетами ведут на якорь `#PREFIX-001`, не на отдельный файл.

## Статусы

Цвет без подписи не использовать. Класс шарика, `data-status` и текст подписи всегда из одной строки.

| data-status | Класс шарика | Подпись |
|---|---|---|
| done | ball-done | Выполнено |
| ready | ball-ready | Можно делать |
| blocked | ball-blocked | Заблокировано |

Других статусов нет. Отдельного статуса «в работе» нет: жёлтый шарик значит, что задачу уже можно делать, в том числе если её уже взяли. Новый план начинает со статуса `ready`, если пользователь не задал другой. Шарики яркие и одинаковые в светлой и тёмной теме.

## Страница

- Сверху липкая панель `#settings`. Слева название файла `{{FILE_NAME}}` и второй строкой короткое описание `{{ONE_LINE}}`. Справа настройки: тема кнопками с иконками (`system`, `light`, `dark`), размер текста (13, 15, 17, 19, 21), шрифт (шесть вариантов из шаблона), ширина контента (60, 80, 100, по умолчанию 80) и кнопка `#menu-toggle`, которая скрывает и показывает левое меню. Значения, включая видимость меню, пишутся в `sessionStorage` и живут, пока открыта вкладка. Короткий скрипт в `head` ставит их до отрисовки. Светлая тема приглушённая: фон и бумага не белые. Шарики статусов яркие в обеих темах. Панель в светлой теме светлая, в тёмной тёмная.
- Слева липкое меню `#menu`. Первый пункт — «Как читать», без шарика, якорь `#how-to-read`. Дальше у пункта шарик статуса. Класс шарика в меню — тот же `ball`, размер фиксирует `.sidemenu .ball`: 8×8, `flex: 0 0 8px`, без внешней обводки. Текст пункта 13px. Код тикета — `.menu-id`, 10px и темнее текста названия. Список пунктов крутится в `.menu-scroll`. Внизу меню статичная строка `.menu-composed`: `📅 Проект открыт {{PLAN_DATE}}`. `{{PLAN_DATE}}` — дата открытия проекта, формат `ДД.ММ.ГГГГ`. Это не дата смены статусов, её не обновляют.
- При прокрутке текущий пункт получает `is-current` (жирный), уже пройденные — `is-past` (светлее). Пункт «Как читать» участвует в этой подсветке.
- В начале колонки блок `#how-to-read`: как читать план и счётчики по `data-status`. Подписи: выполнено, можно делать, заблокировано. Числа считает скрипт страницы.
- Справа колонка `.sheet`. Её ширина — `--content-width`, по умолчанию 80% области справа от меню. Когда меню скрыто, колонка занимает ширину окна.
- Тело тикета: `Зачем`, `Что сделать`, `Готово, когда`. Зависимости — в `.meta` якорями. Эпик — таблица `.subtasks` внутри того же `details`.

## Каркас `docs/todo-plan.html`

```html
<!DOCTYPE html>
<html lang="ru" data-theme="system" data-font="system">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Тикеты — {{PROJECT}}</title>
  <style>
:root {
  --bg: #e4e2db;
  --paper: #f6f4ef;
  --ink: #2c3338;
  --muted: #6e685f;
  --line: #ddd6cb;
  --link: #3d6294;
  --ready: #ffd000;
  --done: #2bd36a;
  --blocked: #ff4d4d;
  --code-bg: #eeeae3;
  --warn-bg: #f3eee2;
  --bad-bg: #f3e9e6;
  --ok-bg: #e6efe8;
  --th-bg: #eeeae3;
  --past: #8d877d;
  --font-sans: "Segoe UI", system-ui, sans-serif;
  --text-size: 15px;
  --settings-h: 52px;
  --chevron: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='8' viewBox='0 0 12 8'%3E%3Cpath d='M1 1.5 6 6.5 11 1.5' fill='none' stroke='%235c6778' stroke-width='1.6' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E");
}

* { box-sizing: border-box; }

body {
  margin: 0;
  background: var(--bg);
  color: var(--ink);
  font: var(--text-size) / 1.5 var(--font-sans);
}

a { color: var(--link); text-decoration: none; }
a:hover { text-decoration: underline; }

.wrap { max-width: 1080px; margin: 0 auto; padding: 22px 20px 48px; }

.how {
  background: var(--paper);
  border: 1px solid var(--line);
  border-radius: 10px;
  padding: 14px 16px 12px;
  margin-bottom: 16px;
  scroll-margin-top: calc(var(--settings-h) + 12px);
}

.how h2 { margin: 0 0 8px; }

.how p { margin: 0 0 10px; }

.how-counts {
  display: flex;
  flex-wrap: wrap;
  gap: 8px 18px;
  margin: 0;
}

.how-counts b { font-variant-numeric: tabular-nums; }

.legend, .card, .note, table {
  background: var(--paper);
  border: 1px solid var(--line);
  border-radius: 10px;
}

.legend, .note { padding: 12px 14px; margin-bottom: 16px; }

.legend { display: flex; flex-wrap: wrap; gap: 14px 22px; align-items: center; }

.ball {
  display: inline-block;
  width: 12px;
  height: 12px;
  border-radius: 50%;
  margin-right: 6px;
  vertical-align: -1px;
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.65), 0 0 0 1px rgba(0, 0, 0, 0.12);
}

.ball-ready { background: var(--ready); }
.ball-done { background: var(--done); }
.ball-blocked { background: var(--blocked); }

.status { white-space: nowrap; font-weight: 600; }

.meta {
  display: flex;
  flex-wrap: wrap;
  gap: 8px 18px;
  color: var(--muted);
  margin: 8px 0 0;
}

code, .code {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 0.92em;
}

code {
  background: var(--code-bg);
  border-radius: 4px;
  padding: 0 4px;
}

pre {
  background: #141b27;
  color: #e7edf6;
  border-radius: 8px;
  padding: 12px 14px;
  overflow: auto;
  line-height: 1.45;
}

pre code { background: transparent; color: inherit; padding: 0; }

table { width: 100%; border-collapse: collapse; margin: 10px 0 18px; overflow: hidden; }

th, td { border-bottom: 1px solid var(--line); text-align: left; vertical-align: top; padding: 8px 10px; }

th { background: var(--th-bg); font-size: 13px; }

tr:last-child td { border-bottom: 0; }

h2 { font-size: 18px; margin: 26px 0 8px; }
h3 { font-size: 15px; margin: 18px 0 6px; }

ul, ol { margin-top: 6px; }
li + li { margin-top: 4px; }

.ticket-list { display: flex; flex-direction: column; gap: 10px; }

.ticket-list a.card {
  display: block;
  color: inherit;
  padding: 12px 14px;
}

.ticket-list a.card:hover { border-color: #b9c7de; text-decoration: none; }

.ticket-list h2 { margin: 0; font-size: 16px; }

.id {
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-weight: 700;
  margin-right: 8px;
}

.summary { margin: 6px 0 0; color: var(--muted); }

.tag {
  display: inline-block;
  border: 1px solid var(--line);
  border-radius: 999px;
  padding: 0 8px;
  font-size: 12px;
  color: var(--muted);
}

.note-bad { background: var(--bad-bg); }
.note-warn { background: var(--warn-bg); }
.note-ok { background: var(--ok-bg); }

nav.crumbs { margin-bottom: 12px; }

.subtasks td:first-child { white-space: nowrap; }

html[data-font="system"] { --font-sans: "Segoe UI", system-ui, sans-serif; }
html[data-font="georgia"] { --font-sans: Georgia, "Times New Roman", serif; }
html[data-font="palatino"] { --font-sans: Palatino, "Palatino Linotype", "Book Antiqua", serif; }
html[data-font="times"] { --font-sans: "Times New Roman", Times, serif; }
html[data-font="verdana"] { --font-sans: Verdana, Geneva, sans-serif; }
html[data-font="mono"] { --font-sans: ui-monospace, "SFMono-Regular", Menlo, Consolas, monospace; }

html[data-theme="light"] { color-scheme: light; }
html[data-theme="dark"] { color-scheme: dark; }

html[data-theme="dark"] {
  --bg: #12161c;
  --paper: #1c2330;
  --ink: #e7edf6;
  --muted: #a8b3c4;
  --link: #9ec0ef;
  --past: #7d8796;
  --line: #2e3848;
  --code-bg: #121820;
  --warn-bg: #3a3016;
  --bad-bg: #3a2222;
  --ok-bg: #173226;
  --th-bg: #242c3b;
  --chevron: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='8' viewBox='0 0 12 8'%3E%3Cpath d='M1 1.5 6 6.5 11 1.5' fill='none' stroke='%23a8b3c4' stroke-width='1.6' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E");
}

@media (prefers-color-scheme: dark) {
  html[data-theme="system"] {
    color-scheme: dark;
    --bg: #12161c;
    --paper: #1c2330;
    --ink: #e7edf6;
    --muted: #a8b3c4;
    --link: #9ec0ef;
  --past: #7d8796;
    --line: #2e3848;
    --code-bg: #121820;
    --warn-bg: #3a3016;
    --bad-bg: #3a2222;
    --ok-bg: #173226;
    --th-bg: #242c3b;
    --chevron: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='8' viewBox='0 0 12 8'%3E%3Cpath d='M1 1.5 6 6.5 11 1.5' fill='none' stroke='%23a8b3c4' stroke-width='1.6' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E");
  }
}

.settings {
  position: sticky;
  top: 0;
  z-index: 30;
  display: flex;
  flex-wrap: wrap;
  justify-content: space-between;
  gap: 10px 20px;
  align-items: center;
  padding: 10px 16px;
  background: var(--paper);
  border-bottom: 1px solid var(--line);
  color: var(--ink);
}

.settings-brand { min-width: 0; flex: 1 1 240px; }

.settings-brand strong {
  display: block;
  color: var(--ink);
  font-size: 15px;
  font-weight: 650;
  line-height: 1.3;
}

.settings-brand span {
  display: block;
  color: var(--muted);
  font-size: 12px;
  line-height: 1.35;
}

.settings-tools {
  display: flex;
  flex-wrap: nowrap;
  align-items: center;
  justify-content: flex-end;
  gap: 10px 14px;
  margin-left: auto;
}

.theme-switch {
  display: inline-flex;
  border: 1px solid var(--line);
  border-radius: 8px;
  overflow: hidden;
  background: var(--bg);
}

.theme-switch button,
#menu-toggle {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 32px;
  height: 30px;
  padding: 0;
  border: 0;
  background: transparent;
  color: var(--muted);
  cursor: pointer;
}

.theme-switch button + button { border-left: 1px solid var(--line); }

.theme-switch button[aria-pressed="true"] {
  background: var(--paper);
  color: var(--ink);
}

#menu-toggle {
  border: 1px solid var(--line);
  border-radius: 8px;
  background: var(--bg);
}

.settings label {
  display: flex;
  align-items: center;
  gap: 8px;
  color: var(--muted);
  font-size: 13px;
}

.settings select {
  font: inherit;
  color: var(--ink);
  background-color: var(--bg);
  background-image: var(--chevron);
  background-repeat: no-repeat;
  background-position: right 12px center;
  background-size: 10px 7px;
  border: 1px solid var(--line);
  border-radius: 6px;
  padding: 4px 30px 4px 8px;
  appearance: none;
  -webkit-appearance: none;
}

.shell {
  display: grid;
  grid-template-columns: 312px minmax(0, 1fr);
  align-items: start;
}

.sidemenu {
  position: sticky;
  top: var(--settings-h);
  display: flex;
  flex-direction: column;
  height: calc(100vh - var(--settings-h));
  overflow: hidden;
  padding: 10px 8px 12px;
  background: var(--paper);
  border-right: 1px solid var(--line);
}

.menu-scroll {
  position: relative;
  flex: 1;
  min-height: 0;
  overflow: auto;
}

.menu-composed {
  flex: none;
  margin: 18px 8px 20px;
  padding-top: 8px;
  border-top: 1px solid var(--line);
  color: var(--muted);
  font-size: 11px;
  line-height: 1.35;
}

.menu-phase {
  margin: 14px 8px 4px;
  color: var(--muted);
  font-size: 11px;
}

.sidemenu a {
  display: flex;
  align-items: center;
  gap: 5px;
  margin: 0;
  padding: 2px 8px;
  border-radius: 6px;
  color: var(--ink);
  font-size: 13px;
  font-weight: 400;
}

html[data-menu="off"] .shell { grid-template-columns: minmax(0, 1fr); }

html[data-menu="off"] .sidemenu { display: none; }

.sidemenu a:hover { text-decoration: none; background: var(--bg); }

.sidemenu a.is-past { color: var(--past); }

.sidemenu a.is-current { color: var(--ink); font-weight: 700; }

.sidemenu .ball {
  width: 8px;
  height: 8px;
  min-width: 8px;
  max-width: 8px;
  min-height: 8px;
  max-height: 8px;
  flex: 0 0 8px;
  margin: 0;
  padding: 0;
  border-radius: 50%;
  line-height: 0;
  font-style: normal;
  aspect-ratio: 1;
  box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.7);
}

.menu-id {
  flex: none;
  font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
  font-size: 10px;
  line-height: 1;
  color: color-mix(in srgb, var(--ink) 72%, #000);
}

.sidemenu a.is-past .menu-id { color: var(--past); }

.menu-title {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.sheet {
  min-width: 0;
  width: var(--content-width, 80%);
  justify-self: center;
}

.sheet .wrap { max-width: none; }

details.ticket {
  margin: 0 0 10px;
  background: var(--paper);
  border: 1px solid var(--line);
  border-radius: 10px;
  scroll-margin-top: calc(var(--settings-h) + 12px);
}

details.ticket > summary {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 12px 14px;
  cursor: pointer;
  list-style: none;
}

details.ticket > summary::-webkit-details-marker { display: none; }

details.ticket > summary::before {
  content: "";
  flex: none;
  width: 0;
  height: 0;
  border-top: 5px solid transparent;
  border-bottom: 5px solid transparent;
  border-left: 6px solid var(--muted);
}

details.ticket[open] > summary::before {
  border-left: 5px solid transparent;
  border-right: 5px solid transparent;
  border-top: 6px solid var(--muted);
  border-bottom: 0;
}

.ticket-title { flex: 1; min-width: 0; }

details.ticket > summary .status { margin-left: auto; }

.ticket-body { padding: 0 14px 14px; }

.ticket-body h2 { margin: 26px 0 8px; font-size: 18px; }

@media (max-width: 860px) {
  .shell { grid-template-columns: 1fr; }

  .sidemenu {
    position: sticky;
    top: var(--settings-h);
    height: auto;
    max-height: 38vh;
    border-right: 0;
    border-bottom: 1px solid var(--line);
  }
}
  </style>
  <script>
    (function () {
      try {
        var theme = sessionStorage.getItem("plan-theme") || "system";
        var size = sessionStorage.getItem("plan-size") || "15";
        var font = sessionStorage.getItem("plan-font") || "system";
        var width = sessionStorage.getItem("plan-width") || "80";
        var menu = sessionStorage.getItem("plan-menu") || "on";
        document.documentElement.dataset.theme = theme;
        document.documentElement.dataset.font = font;
        document.documentElement.dataset.menu = menu === "off" ? "off" : "on";
        document.documentElement.style.setProperty("--text-size", size + "px");
        document.documentElement.style.setProperty("--content-width", width + "%");
      } catch (error) {}
    })();
  </script>
</head>
<body>
  <div class="settings" id="settings">
    <div class="settings-brand">
      <strong>{{FILE_NAME}}</strong>
      <span>{{ONE_LINE}}</span>
    </div>
    <div class="settings-tools">
    <div class="theme-switch" role="group" aria-label="Тема">
      <button type="button" data-theme-value="system" title="Системная" aria-pressed="false"><svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><rect x="1.5" y="2.5" width="13" height="9" rx="1.2" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M6 13.5h4M8 11.5v2" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg></button>
      <button type="button" data-theme-value="light" title="Светлая" aria-pressed="false"><svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><circle cx="8" cy="8" r="2.3" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M8 1.6v1.5M8 12.9v1.5M1.6 8h1.5M12.9 8h1.5M3.4 3.4l1.1 1.1M11.5 11.5l1.1 1.1M12.6 3.4l-1.1 1.1M4.5 11.5l-1.1 1.1" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg></button>
      <button type="button" data-theme-value="dark" title="Тёмная" aria-pressed="false"><svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><path d="M10.4 2.1a5.3 5.3 0 1 0 3.5 9 4.3 4.3 0 0 1-3.5-9z" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round"/></svg></button>
    </div>
    <label>Размер
      <select id="font-size">
        <option value="13">13</option>
        <option value="15">15</option>
        <option value="17">17</option>
        <option value="19">19</option>
        <option value="21">21</option>
      </select>
    </label>
    <label>Шрифт
      <select id="font-family">
        <option value="system">Системный</option>
        <option value="georgia">Georgia</option>
        <option value="palatino">Palatino</option>
        <option value="times">Times New Roman</option>
        <option value="verdana">Verdana</option>
        <option value="mono">Моноширинный</option>
      </select>
    </label>
    <label>Ширина
      <select id="content-width">
        <option value="60">60%</option>
        <option value="80" selected>80%</option>
        <option value="100">100%</option>
      </select>
    </label>
    <button type="button" id="menu-toggle" title="Скрыть меню" aria-expanded="true" aria-label="Меню"><svg viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><rect x="1.5" y="2.5" width="13" height="11" rx="1.2" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M6 2.5v11" fill="none" stroke="currentColor" stroke-width="1.4"/></svg></button>
    </div>
  </div>
  <div class="shell">
    <nav class="sidemenu" id="menu">
      <div class="menu-scroll">
      <a class="menu-guide" href="#how-to-read"><span class="menu-title">Как читать</span></a>
      <p class="menu-phase">1. Группа</p>
      <a href="#PREFIX-001"><i class="ball ball-ready"></i><span class="menu-id">PREFIX-001</span><span class="menu-title">{{TITLE}}</span></a>
      </div>
      <p class="menu-composed">📅 Проект открыт {{PLAN_DATE}}</p>
    </nav>
    <div class="sheet">
      <main class="wrap">
        <section class="how" id="how-to-read">
          <h2>Как читать</h2>
          <p>{{HOW_TO_READ}}</p>
          <p class="how-counts">
            <span><i class="ball ball-done"></i>Выполнено <b data-count="done">0</b></span>
            <span><i class="ball ball-ready"></i>Можно делать <b data-count="ready">0</b></span>
            <span><i class="ball ball-blocked"></i>Заблокировано <b data-count="blocked">0</b></span>
          </p>
        </section>
        <h2>1. Группа</h2>
        <section class="ticket-list">
          <details class="ticket" id="PREFIX-001" data-status="ready">
            <summary>
              <i class="ball ball-ready"></i>
              <span class="id">PREFIX-001</span>
              <span class="ticket-title">{{TITLE}}</span>
              <span class="status">Можно делать</span>
            </summary>
            <div class="ticket-body">
              <p class="meta"><span class="tag">{{TAG}}</span></p>
              <h2>Зачем</h2>
              <p>{{WHY}}</p>
              <h2>Что сделать</h2>
              <ol><li>{{STEP}}</li></ol>
              <h2>Готово, когда</h2>
              <ul><li>{{DONE}}</li></ul>
            </div>
          </details>
        </section>
      </main>
    </div>
  </div>
  <script>
(function () {
  var root = document.documentElement;
  var themeButtons = Array.prototype.slice.call(document.querySelectorAll("[data-theme-value]"));
  var themeValue = "system";
  var size = document.getElementById("font-size");
  var font = document.getElementById("font-family");
  var width = document.getElementById("content-width");
  var menuToggle = document.getElementById("menu-toggle");
  var menuOpen = true;
  var settings = document.getElementById("settings");
  var menu = document.getElementById("menu");
  var menuScroll = menu ? menu.querySelector(".menu-scroll") || menu : null;
  var tickets = Array.prototype.slice.call(document.querySelectorAll("details.ticket"));
  var links = menu ? Array.prototype.slice.call(menu.querySelectorAll("a[href^='#']")) : [];
  var sections = links.map(function (link) {
    return document.getElementById(decodeURIComponent(link.getAttribute("href").slice(1)));
  });

  function read(key, fallback) {
    try {
      return sessionStorage.getItem(key) || fallback;
    } catch (error) {
      return fallback;
    }
  }

  function write(key, value) {
    try {
      sessionStorage.setItem(key, value);
    } catch (error) {
      return;
    }
  }

  function applySettings() {
    root.dataset.theme = themeValue;
    root.dataset.font = font.value;
    root.dataset.menu = menuOpen ? "on" : "off";
    root.style.setProperty("--text-size", size.value + "px");
    root.style.setProperty("--content-width", width.value + "%");
    write("plan-theme", themeValue);
    write("plan-size", size.value);
    write("plan-font", font.value);
    write("plan-width", width.value);
    write("plan-menu", menuOpen ? "on" : "off");
    themeButtons.forEach(function (button) {
      button.setAttribute("aria-pressed", button.getAttribute("data-theme-value") === themeValue ? "true" : "false");
    });
    if (menuToggle) {
      menuToggle.setAttribute("aria-expanded", menuOpen ? "true" : "false");
      menuToggle.title = menuOpen ? "Скрыть меню" : "Показать меню";
    }
    fitMenu();
  }

  function fitMenu() {
    if (!settings) return;
    root.style.setProperty("--settings-h", settings.offsetHeight + "px");
  }

  themeValue = read("plan-theme", "system");
  size.value = read("plan-size", "15");
  font.value = read("plan-font", "system");
  width.value = read("plan-width", "80");
  menuOpen = read("plan-menu", "on") !== "off";
  applySettings();

  themeButtons.forEach(function (button) {
    button.addEventListener("click", function () {
      themeValue = button.getAttribute("data-theme-value");
      applySettings();
    });
  });
  size.addEventListener("change", applySettings);
  font.addEventListener("change", applySettings);
  width.addEventListener("change", applySettings);
  if (menuToggle) {
    menuToggle.addEventListener("click", function () {
      menuOpen = !menuOpen;
      applySettings();
    });
  }
  window.addEventListener("resize", fitMenu);

  var counts = { done: 0, ready: 0, blocked: 0 };
  tickets.forEach(function (ticket) {
    var status = ticket.getAttribute("data-status");
    if (counts[status] !== undefined) counts[status] += 1;
  });
  Array.prototype.forEach.call(document.querySelectorAll("[data-count]"), function (node) {
    node.textContent = String(counts[node.getAttribute("data-count")] || 0);
  });

  function openTicket(id) {
    var ticket = document.getElementById(id);
    if (ticket && ticket.tagName === "DETAILS") ticket.open = true;
  }

  function markMenu() {
    if (!links.length) return;
    var line = settings ? settings.getBoundingClientRect().bottom + 4 : 0;
    var current = 0;
    sections.forEach(function (section, index) {
      if (section && section.getBoundingClientRect().top <= line) current = index;
    });
    links.forEach(function (link, index) {
      link.classList.toggle("is-current", index === current);
      link.classList.toggle("is-past", index < current);
    });
    var active = links[current];
    if (active && menuScroll && menuOpen) {
      var top = active.offsetTop;
      var bottom = top + active.offsetHeight;
      if (top < menuScroll.scrollTop) menuScroll.scrollTop = top - 8;
      else if (bottom > menuScroll.scrollTop + menuScroll.clientHeight) {
        menuScroll.scrollTop = bottom - menuScroll.clientHeight + 8;
      }
    }
  }

  var frame = 0;
  function onScroll() {
    if (frame) return;
    frame = window.requestAnimationFrame(function () {
      frame = 0;
      markMenu();
    });
  }

  document.addEventListener("click", function (event) {
    var link = event.target.closest("a[href^='#']");
    if (!link) return;
    openTicket(link.getAttribute("href").slice(1));
  });

  tickets.forEach(function (ticket) {
    ticket.addEventListener("toggle", onScroll);
  });

  window.addEventListener("scroll", onScroll, { passive: true });
  window.addEventListener("resize", onScroll);

  if (location.hash.length > 1) openTicket(decodeURIComponent(location.hash.slice(1)));
  markMenu();
})();
  </script>
</body>
</html>

```

Блок `details` из примера повторить для каждого тикета. В меню — такой же порядок и те же шарики.

## Как поставить такую же задачу в другом проекте

Скопируй этот файл в новый репозиторий по пути `docs/ticket-plan-boilerplate.md` или приложи его в чат. В задание вставь промпт ниже и замени префикс и список задач.

```text
Изучи этот проект. Код продукта не меняй.

Оформи задачи одним планом строго по файлу docs/ticket-plan-boilerplate.md.
Если файла в репозитории нет, возьми приложенный бойлерплейт.
Бойлерплейт не переписывай и задачи в него не добавляй.

Соблюди формат:
- один файл docs/todo-plan.html
- стили в <style> в head, скрипт в <script> перед </body>, скопируй их из каркаса дословно
- отдельные css и js не создавать
- все тикеты внутри этого файла, описания в details без open
- слева меню со шариками статусов, первым пунктом «Как читать», текущий пункт жирный, пройденные светлее
- в начале страницы блок «Как читать» со счётчиками: выполнено, можно делать, заблокировано
- сверху слева название файла и короткое описание, справа настройки
- тема кнопками с иконками, кнопка скрывает и показывает левое меню
- светлая тема приглушённая, верхняя панель в ней светлая, шарики статусов яркие в обеих темах
- внизу меню «📅 Проект открыт ДД.ММ.ГГГГ», это дата открытия проекта, не дата смены статусов
- настройки только в sessionStorage
- код PREFIX-001 и далее по порядку выполнения
- статусы только три: «Выполнено» зелёный ball-done data-status="done"; «Можно делать» жёлтый ball-ready data-status="ready"; «Заблокировано» красный ball-blocked data-status="blocked"
- отдельного статуса «в работе» нет
- секции тикета: Зачем, Что сделать, Готово когда
- большую задачу, которую я назвал одной, оформи эпиком с подпунктами PREFIX-00N-1 в том же блоке
- в тикеты запиши конкретные файлы и проверки этого проекта, без общих советов
- страницы на русском

Префикс кодов: PREFIX

Задачи:
1. ...
2. ...
```
