import { useEffect, useState } from "react";
import { Link } from "wouter";
import {
  ArrowRight,
  Check,
  CheckCircle2,
  ChevronRight,
  ClipboardCheck,
  Code2,
  Copy,
  ExternalLink,
  Info,
  KeyRound,
  LockKeyhole,
  Package,
  PhoneCall,
  Printer,
  Radio,
  Server,
  ShieldCheck,
  Smartphone,
  Terminal,
  Wifi,
} from "lucide-react";

const dependencyCode = `dependencies:
  sipkit_flutter:
    git:
      url: https://github.com/sipkit/sipkit_flutter.git
      ref: v0.1.0`;

const dartCode = `import 'package:sipkit_flutter/sipkit_flutter.dart';

Future<void> startSipKit() async {
  // WebRTC is the default engine and the recommended first test path.
  final client = SipKitClient();

  await client.activate(
    licenseKey: 'pk_live_REPLACE_WITH_PROVIDER_KEY',
    baseUrl: 'https://license.example-provider.com',
    appId: 'com.example.provider_softphone',
    deviceId: 'REPLACE_WITH_DEVICE_ID',
  );

  final account = await client.addAccount(
    SipKitAccountConfig(
      username: 'REPLACE_SIP_USERNAME',
      password: 'REPLACE_SIP_PASSWORD',
      domain: 'pbx.example-provider.com',
      wsUrl: 'wss://pbx.example-provider.com:8089/ws',
      displayName: 'REPLACE_DISPLAY_NAME',
      authUsername: 'REPLACE_IF_DIFFERENT',
      registerOnAdd: true,
    ),
  );

  account.status.listen((status) {
    print('Registration status: $status');
  });

  final call = await client.makeCall(
    account.id,
    'sip:REPLACE_DESTINATION@pbx.example-provider.com',
  );

  call.state.listen((state) {
    print('Call state: $state');
  });
}`;

const iosCode = `<key>NSMicrophoneUsageDescription</key>
<string>SipKit needs the microphone for voice calls.</string>
<key>NSCameraUsageDescription</key>
<string>SipKit needs the camera for video calls.</string>`;

const androidCode = `<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.CAMERA" />`;

const checklistItems = [
  {
    id: "tag",
    title: "Install the tagged SDK",
    detail: "Run flutter pub get and confirm the dependency resolves to v0.1.0.",
  },
  {
    id: "license",
    title: "Activate with a live provider key",
    detail: "Use the pk_live_ key issued for this app and the licensing origin only.",
  },
  {
    id: "permissions",
    title: "Add microphone and network permissions",
    detail: "Apply the iOS and Android snippets before requesting runtime access.",
  },
  {
    id: "account",
    title: "Register a real SIP-over-WebSocket account",
    detail: "The SIP username, password, domain, and WSS URL come from your PBX.",
  },
  {
    id: "call",
    title: "Place a first audio test call",
    detail: "Watch account.status and call.state in the debug console.",
  },
];

function CopyButton({ code, testId }: { code: string; testId: string }) {
  const [copied, setCopied] = useState(false);

  const handleCopy = async () => {
    if (!navigator.clipboard) return;
    await navigator.clipboard.writeText(code);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1800);
  };

  return (
    <button
      type="button"
      onClick={handleCopy}
      className="no-print inline-flex items-center gap-2 rounded-md border border-white/10 bg-white/[0.07] px-3 py-1.5 text-xs font-semibold text-slate-200 transition-all hover:border-teal-300/50 hover:bg-teal-300/10 hover:text-teal-100 active:scale-[.98]"
      data-testid={testId}
      aria-label={copied ? "Code copied" : "Copy code"}
    >
      {copied ? <Check className="h-3.5 w-3.5 text-teal-300" /> : <Copy className="h-3.5 w-3.5" />}
      {copied ? "Copied" : "Copy"}
    </button>
  );
}

function CodeBlock({
  code,
  label,
  language,
  testId,
}: {
  code: string;
  label: string;
  language: string;
  testId: string;
}) {
  return (
    <div className="min-w-0 max-w-full overflow-hidden rounded-xl border border-slate-700/80 bg-[#172632] shadow-[0_18px_45px_-28px_rgba(14,37,48,.65)]">
      <div className="flex items-center justify-between border-b border-white/10 px-4 py-3">
        <div className="flex min-w-0 items-center gap-2.5">
          <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded bg-teal-300/10 text-teal-300">
            <Code2 className="h-3.5 w-3.5" />
          </span>
          <span className="truncate text-xs font-semibold uppercase tracking-[.15em] text-slate-300">{label}</span>
          <span className="hidden rounded bg-white/[0.07] px-2 py-0.5 font-mono text-[10px] text-slate-500 sm:inline">{language}</span>
        </div>
        <CopyButton code={code} testId={testId} />
      </div>
      <pre className="code-scroll max-h-[34rem] overflow-x-auto p-5 text-[12px] leading-[1.8] text-slate-200 sm:p-6 sm:text-[13px]">
        <code>{code}</code>
      </pre>
    </div>
  );
}

function SectionHeading({
  eyebrow,
  title,
  description,
  number,
}: {
  eyebrow: string;
  title: string;
  description?: string;
  number: string;
}) {
  return (
    <div className="mb-7 flex gap-4">
      <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-[#e5a16e]/15 font-mono text-xs font-bold text-[#bb633f] ring-1 ring-[#bb633f]/20">
        {number}
      </div>
      <div>
        <div className="mb-1.5 flex items-center gap-2 text-[11px] font-bold uppercase tracking-[.18em] text-[#bb633f]">
          <span>{eyebrow}</span>
          <span className="h-px w-8 bg-[#bb633f]/35" />
        </div>
        <h2 className="text-2xl font-bold tracking-[-0.035em] text-[#213746] sm:text-[28px]">{title}</h2>
        {description && <p className="mt-2 max-w-2xl text-[15px] leading-7 text-[#526773]">{description}</p>}
      </div>
    </div>
  );
}

function ReplaceRow({
  label,
  sample,
  suppliedBy,
  note,
}: {
  label: string;
  sample: string;
  suppliedBy: string;
  note: string;
}) {
  return (
    <div className="grid gap-3 border-t border-[#ded9ce] py-4 first:border-t-0 sm:grid-cols-[1.05fr_1.25fr_1fr] sm:items-start sm:gap-5">
      <div>
        <div className="text-sm font-bold text-[#213746]">{label}</div>
        <div className="mt-1 font-mono text-[11px] text-[#a75b40]">{sample}</div>
      </div>
      <div className="text-sm leading-6 text-[#526773]">{note}</div>
      <div className="inline-flex w-fit items-center gap-1.5 rounded-full bg-[#e3f0eb] px-2.5 py-1 text-[11px] font-bold text-[#23665d]">
        <ArrowRight className="h-3 w-3" />
        {suppliedBy}
      </div>
    </div>
  );
}

export default function Install() {
  const [checked, setChecked] = useState<Record<string, boolean>>({});
  const checkedCount = Object.values(checked).filter(Boolean).length;

  useEffect(() => {
    const previousTitle = document.title;
    document.title = "SipKit installation guide · v0.1.0";
    return () => {
      document.title = previousTitle;
    };
  }, []);

  const toggleChecklist = (id: string) => {
    setChecked((current) => ({ ...current, [id]: !current[id] }));
  };

  return (
    <div className="install-guide min-h-[100dvh] overflow-x-hidden text-[#213746]">
      <header className="no-print sticky top-0 z-20 border-b border-[#d9d6cc]/80 bg-[#f5f2ea]/90 backdrop-blur-xl">
        <div className="mx-auto flex h-16 max-w-7xl items-center justify-between px-5 sm:px-8">
          <Link
            href="/"
            className="group flex items-center gap-3"
            data-testid="link-sipkit-ops"
          >
            <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-[#213746] text-[#f5f2ea] shadow-sm transition-transform group-hover:-rotate-6">
              <Radio className="h-4 w-4" />
            </span>
            <span className="text-sm font-bold tracking-[-.02em] text-[#213746]">SipKit <span className="font-normal text-[#78868b]">/ installation</span></span>
          </Link>
          <div className="flex items-center gap-2 sm:gap-4">
            <span className="hidden items-center gap-1.5 font-mono text-[10px] font-bold uppercase tracking-[.14em] text-[#628078] sm:flex">
              <span className="sipkit-pulse h-1.5 w-1.5 rounded-full bg-[#3e9a83]" />
              Provider handoff
            </span>
            <button
              type="button"
              onClick={() => window.print()}
              className="inline-flex items-center gap-2 rounded-md border border-[#cfcfc5] bg-[#f9f7f1] px-3 py-2 text-xs font-bold text-[#526773] transition-colors hover:border-[#9aaea5] hover:bg-[#eaf2ee] hover:text-[#23665d]"
              data-testid="button-print-guide"
            >
              <Printer className="h-3.5 w-3.5" />
              <span className="hidden sm:inline">Save as PDF</span>
              <span className="sm:hidden">Print</span>
            </button>
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-7xl px-5 pb-24 pt-9 sm:px-8 lg:pt-14">
        <div className="grid min-w-0 gap-14 lg:grid-cols-[minmax(0,1fr)_220px] lg:gap-20">
          <div className="min-w-0">
            <section className="install-grid sipkit-rise relative min-w-0 max-w-full overflow-hidden rounded-2xl border border-[#d7d8cc] bg-[#eef1e9] px-6 py-9 sm:px-10 sm:py-12 lg:px-14">
              <div className="relative z-10 w-full max-w-3xl">
                <div className="mb-5 inline-flex items-center gap-2 rounded-full border border-[#8db6a7]/50 bg-[#f5f8f1]/75 px-3 py-1.5 text-[11px] font-bold uppercase tracking-[.17em] text-[#23665d]">
                  <Package className="h-3.5 w-3.5" />
                  SDK release <span className="font-mono text-[#bb633f]">v0.1.0</span>
                </div>
                <h1 className="max-w-3xl text-[clamp(2.55rem,6vw,5.35rem)] font-bold leading-[.95] tracking-[-.065em] text-[#213746]">
                  Put your first call<br />
                  <span className="text-[#bb633f]">on the wire.</span>
                </h1>
                <p className="mt-7 max-w-xl text-base leading-7 text-[#526773] sm:text-lg sm:leading-8">
                  A practical handoff for providers integrating SipKit into a Flutter softphone. Install the tagged SDK, activate your entitlement, register a real SIP-over-WebSocket account, and verify an audio call in one focused pass.
                </p>
                <div className="mt-8 flex max-w-full flex-wrap items-center gap-3">
                  <a
                    href="#quickstart"
                    className="group inline-flex items-center gap-2 rounded-md bg-[#23665d] px-4 py-2.5 text-sm font-bold text-[#f5f7ef] shadow-[0_8px_18px_-10px_rgba(35,102,93,.8)] transition-all hover:-translate-y-0.5 hover:bg-[#1e554e]"
                    data-testid="link-start-quickstart"
                  >
                    Start with quickstart
                    <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" />
                  </a>
                  <a
                    href="#checklist"
                    className="inline-flex items-center gap-2 rounded-md px-4 py-2.5 text-sm font-bold text-[#526773] transition-colors hover:bg-[#e0e8df] hover:text-[#23665d]"
                    data-testid="link-first-test-checklist"
                  >
                    <ClipboardCheck className="h-4 w-4" />
                    First-test checklist
                  </a>
                </div>
              </div>
              <div className="absolute -right-10 -top-8 hidden h-64 w-64 rounded-full border-[22px] border-[#3e9a83]/15 sm:block" />
              <div className="absolute -bottom-20 right-28 hidden h-48 w-48 rounded-full border-[16px] border-[#e5a16e]/20 sm:block" />
              <div className="absolute bottom-8 right-10 hidden h-20 w-20 rounded-2xl border border-[#3e9a83]/25 bg-[#f4f5eb]/70 shadow-[0_20px_50px_-24px_rgba(35,102,93,.7)] sm:flex sm:items-center sm:justify-center">
                <Wifi className="h-7 w-7 text-[#23665d]" />
              </div>
            </section>

            <section id="quickstart" className="install-section sipkit-rise sipkit-rise-delay-1 scroll-mt-24 pt-16 sm:pt-20">
              <SectionHeading
                number="01"
                eyebrow="Quickstart"
                title="Install the exact SDK you were handed."
                description="Pin the release while you integrate. This keeps your provider test repeatable and makes future upgrades an explicit choice."
              />
              <CodeBlock code={dependencyCode} label="pubspec.yaml" language="YAML" testId="button-copy-dependency" />
              <div className="mt-4 flex items-start gap-3 rounded-xl border border-[#cadfd4] bg-[#e7f1eb] p-4 text-sm leading-6 text-[#35645e]">
                <Info className="mt-0.5 h-4 w-4 shrink-0 text-[#3e9a83]" />
                <p><strong>Why pin?</strong> Keep the SDK tag and the test notes together. Move to a newer tag only after you have a passing call on this version.</p>
              </div>
            </section>

            <section className="install-section sipkit-rise sipkit-rise-delay-2 scroll-mt-24 pt-16 sm:pt-20" id="activation">
              <SectionHeading
                number="02"
                eyebrow="Activate + connect"
                title="One complete path from key to call."
                description="The default SipKitClient uses the WebRTC engine, which is the recommended first test path on every Flutter platform. Native PJSIP engines can follow once the transport is proven."
              />
              <CodeBlock code={dartCode} label="lib/sipkit_smoke_test.dart" language="DART" testId="button-copy-dart-example" />
              <div className="mt-5 grid gap-3 sm:grid-cols-3">
                <div className="rounded-xl border border-[#d9d6cc] bg-[#faf8f2] p-4">
                  <KeyRound className="mb-3 h-4 w-4 text-[#bb633f]" />
                  <h3 className="text-sm font-bold">Activate first</h3>
                  <p className="mt-1.5 text-xs leading-5 text-[#64757c]">Licensing gates account registration and calls. The base URL is the licensing origin, never an admin or API path.</p>
                </div>
                <div className="rounded-xl border border-[#d9d6cc] bg-[#faf8f2] p-4">
                  <Server className="mb-3 h-4 w-4 text-[#23665d]" />
                  <h3 className="text-sm font-bold">Register second</h3>
                  <p className="mt-1.5 text-xs leading-5 text-[#64757c]">Your provider supplies the SIP credentials, PBX domain, and secure WebSocket URL.</p>
                </div>
                <div className="rounded-xl border border-[#d9d6cc] bg-[#faf8f2] p-4">
                  <PhoneCall className="mb-3 h-4 w-4 text-[#bb633f]" />
                  <h3 className="text-sm font-bold">Call third</h3>
                  <p className="mt-1.5 text-xs leading-5 text-[#64757c]">Listen to account and call state while making a simple audio call to a known test destination.</p>
                </div>
              </div>
              <div className="mt-5 rounded-xl border-l-4 border-[#bb633f] bg-[#fbede5] px-5 py-4 text-sm leading-6 text-[#754c3e]">
                <strong className="text-[#82482e]">Transport requirement:</strong> the PBX must support secure SIP-over-WebSocket (WSS). A regular SIP UDP/TCP registrar is not enough for the WebRTC first test.
              </div>
            </section>

            <section className="install-section scroll-mt-24 pt-16 sm:pt-20" id="replace-values">
              <SectionHeading
                number="03"
                eyebrow="Provider inputs"
                title="Know exactly what to replace."
                description="The values below are intentionally obvious samples. Replace every value marked as a provider input before sharing a build or making a call."
              />
              <div className="overflow-hidden rounded-xl border border-[#d9d6cc] bg-[#faf8f2] px-5 sm:px-7">
                <ReplaceRow label="License key" sample="pk_live_REPLACE_WITH_PROVIDER_KEY" suppliedBy="SipKit / provider" note="Use the live key issued for this application. Keep it out of public repositories and do not substitute an admin API key." />
                <ReplaceRow label="Licensing base URL" sample="https://license.example-provider.com" suppliedBy="SipKit operator" note="Use the origin of the licensing service. Do not append /admin or /api; the SDK adds the required path." />
                <ReplaceRow label="App identity" sample="com.example.provider_softphone" suppliedBy="Provider app team" note="Replace the sample package ID with your real app ID. It identifies the app during activation." />
                <ReplaceRow label="SIP credentials" sample="REPLACE_SIP_USERNAME / REPLACE_SIP_PASSWORD" suppliedBy="SIP provider" note="These are your PBX account credentials, independent from the SipKit license. Treat the password as a secret." />
                <ReplaceRow label="Domain + WSS URL" sample="pbx.example-provider.com / wss://…/ws" suppliedBy="PBX team" note="Use the registrar domain and the secure SIP-over-WebSocket endpoint exposed by your PBX." />
                <ReplaceRow label="Call destination" sample="sip:REPLACE_DESTINATION@pbx.example-provider.com" suppliedBy="Test owner" note="Point the first call at a known extension or SIP URI that is online and ready to answer." />
              </div>
              <div className="mt-4 flex items-start gap-3 rounded-xl border border-[#ead5be] bg-[#fff6eb] p-4 text-sm leading-6 text-[#795b45]">
                <LockKeyhole className="mt-0.5 h-4 w-4 shrink-0 text-[#bb633f]" />
                <p><strong>Credential boundary:</strong> SipKit activation proves entitlement; it does not provide SIP credentials. The provider supplies and controls the account values used by <span className="font-mono text-xs">SipKitAccountConfig</span>.</p>
              </div>
            </section>

            <section className="install-section scroll-mt-24 pt-16 sm:pt-20" id="permissions">
              <SectionHeading
                number="04"
                eyebrow="Platform setup"
                title="Give the call a microphone and a route out."
                description="Add the permission declarations before testing. Runtime permission prompts still need to be requested by your Flutter app at the right moment."
              />
              <div className="grid gap-5 lg:grid-cols-2">
                <div>
                  <div className="mb-3 flex items-center gap-2 text-sm font-bold text-[#213746]">
                    <Smartphone className="h-4 w-4 text-[#bb633f]" />
                    iOS · Info.plist
                  </div>
                  <CodeBlock code={iosCode} label="ios/Runner/Info.plist" language="XML" testId="button-copy-ios-permissions" />
                </div>
                <div>
                  <div className="mb-3 flex items-center gap-2 text-sm font-bold text-[#213746]">
                    <Terminal className="h-4 w-4 text-[#23665d]" />
                    Android · app manifest
                  </div>
                  <CodeBlock code={androidCode} label="android/app/src/main/AndroidManifest.xml" language="XML" testId="button-copy-android-permissions" />
                </div>
              </div>
              <p className="mt-4 text-sm leading-6 text-[#64757c]">
                For native background calling, review the PJSIP-specific CallKit / ConnectionService setup separately. Keep the default WebRTC engine for this first foreground verification.
              </p>
            </section>

            <section className="install-section scroll-mt-24 pt-16 sm:pt-20" id="checklist">
              <SectionHeading
                number="05"
                eyebrow="First test"
                title="A five-minute handoff checklist."
                description="Mark each gate as you go. Your progress stays on this page while you work through the test."
              />
              <div className="overflow-hidden rounded-xl border border-[#d9d6cc] bg-[#faf8f2]">
                <div className="flex items-center justify-between border-b border-[#ded9ce] bg-[#f3f0e7] px-5 py-4">
                  <span className="text-sm font-bold text-[#213746]">Ready when all five gates are green.</span>
                  <span className="font-mono text-xs font-bold text-[#23665d]" data-testid="status-checklist-progress">{checkedCount}/5 complete</span>
                </div>
                <div className="p-2">
                  {checklistItems.map((item) => {
                    const isChecked = Boolean(checked[item.id]);
                    return (
                      <button
                        type="button"
                        key={item.id}
                        onClick={() => toggleChecklist(item.id)}
                        className="group flex w-full items-start gap-4 rounded-lg px-3 py-4 text-left transition-colors hover:bg-[#edf3ed]"
                        data-testid={`button-check-${item.id}`}
                        aria-pressed={isChecked}
                      >
                        <span className={`mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full border transition-all ${isChecked ? "border-[#23665d] bg-[#23665d] text-white" : "border-[#aebdb5] bg-[#faf8f2] text-transparent group-hover:border-[#3e9a83]"}`}>
                          <Check className="h-3 w-3" />
                        </span>
                        <span className="min-w-0">
                          <span className={`block text-sm font-bold ${isChecked ? "text-[#23665d] line-through decoration-[#87aa9e]" : "text-[#213746]"}`}>{item.title}</span>
                          <span className="mt-1 block text-xs leading-5 text-[#718087]">{item.detail}</span>
                        </span>
                      </button>
                    );
                  })}
                </div>
              </div>
              {checkedCount === checklistItems.length && (
                <div className="sipkit-rise mt-4 flex items-center gap-3 rounded-xl border border-[#bcd8ca] bg-[#e5f2e8] p-4 text-sm font-semibold text-[#23665d]" data-testid="status-checklist-complete">
                  <CheckCircle2 className="h-5 w-5" />
                  All gates checked. You have a clean first-call handoff.
                </div>
              )}
            </section>

            <section className="install-section scroll-mt-24 pb-10 pt-16 sm:pt-20" id="troubleshooting">
              <SectionHeading
                number="06"
                eyebrow="Troubleshooting"
                title="When the first call does not connect."
                description="Start with the earliest failing signal. Registration must be healthy before media or destination debugging can help."
              />
              <div className="grid gap-3">
                {[
                  ["Activation fails", "Confirm the key begins with pk_live_, the key is active for this app, and baseUrl is only the licensing origin — never /admin or /api."],
                  ["Account stays unregistered", "Check username, password, domain, and wsUrl independently. The wsUrl must begin with wss://, have a valid certificate, and point to a SIP-over-WebSocket endpoint."],
                  ["Registration works but audio is silent", "Confirm microphone permission, browser/device audio routing, and the PBX ICE/STUN configuration. Watch call.state before changing the destination."],
                  ["The destination never rings", "Use a known online extension and a complete SIP URI. Confirm the PBX accepts the account's domain and that outbound routing permits the target."],
                ].map(([title, detail]) => (
                  <details key={title} className="group rounded-xl border border-[#d9d6cc] bg-[#faf8f2] px-5 py-4 open:bg-[#f4f1e8]">
                    <summary
                      className="flex cursor-pointer list-none items-center justify-between gap-4 text-sm font-bold text-[#213746]"
                      data-testid={`button-troubleshooting-${title.toLowerCase().replace(/\s+/g, "-")}`}
                    >
                      <span className="flex items-center gap-3"><span className="h-1.5 w-1.5 rounded-full bg-[#bb633f]" />{title}</span>
                      <ChevronRight className="h-4 w-4 shrink-0 text-[#83918e] transition-transform group-open:rotate-90" />
                    </summary>
                    <p className="ml-4 mt-3 max-w-2xl border-l border-[#c8d5ce] pl-4 text-sm leading-6 text-[#64757c]">{detail}</p>
                  </details>
                ))}
              </div>
            </section>
          </div>

          <aside className="no-print hidden lg:block">
            <div className="sticky top-24">
              <div className="mb-4 text-[10px] font-bold uppercase tracking-[.2em] text-[#9b6a55]">In this handoff</div>
              <nav className="border-l border-[#d3d6ca]">
                {[
                  ["#quickstart", "Install", "01"],
                  ["#activation", "Activate + connect", "02"],
                  ["#replace-values", "Provider inputs", "03"],
                  ["#permissions", "Platform setup", "04"],
                  ["#checklist", "First test", "05"],
                  ["#troubleshooting", "Troubleshooting", "06"],
                ].map(([href, label, number]) => (
                  <a
                    key={href}
                    href={href}
                    className="group -ml-px flex items-center justify-between border-l border-transparent px-4 py-2.5 text-xs font-semibold text-[#718087] transition-colors hover:border-[#bb633f] hover:text-[#23665d]"
                    data-testid={`link-guide-${number}`}
                  >
                    {label}
                    <span className="font-mono text-[10px] text-[#aeb7b0] group-hover:text-[#bb633f]">{number}</span>
                  </a>
                ))}
              </nav>
              <div className="mt-10 rounded-xl border border-[#d9d6cc] bg-[#eef1e9] p-4">
                <ShieldCheck className="h-5 w-5 text-[#23665d]" />
                <p className="mt-3 text-xs font-bold leading-5 text-[#355d58]">A safe handoff keeps license values and SIP secrets on the provider side.</p>
                <p className="mt-2 text-[11px] leading-5 text-[#718087]">Share this page freely. Replace only the marked values in your app.</p>
              </div>
            </div>
          </aside>
        </div>

        <footer className="mt-14 flex flex-col justify-between gap-4 border-t border-[#d9d6cc] pt-6 text-xs text-[#78868b] sm:flex-row sm:items-center">
          <div className="flex items-center gap-2">
            <Radio className="h-3.5 w-3.5 text-[#23665d]" />
            SipKit provider installation guide · <span className="font-mono">v0.1.0</span>
          </div>
          <Link href="/" className="inline-flex items-center gap-1.5 font-bold text-[#526773] transition-colors hover:text-[#23665d]" data-testid="link-return-to-ops">
            Return to SipKit Ops
            <ExternalLink className="h-3.5 w-3.5" />
          </Link>
        </footer>
      </main>
    </div>
  );
}