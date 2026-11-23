> **SUPERSEDED — do not work from this file.**
>
> Written before the live policy was checked. Two of its premises turned out
> to be wrong: the registered company name is already published (The Social
> Globe Ltd, 13923693), so the blank below is stale; and the provider list
> needed correcting rather than adding to.
>
> Use **`appreview/privacy-policy-section-4.md`** instead. Kept only so the
> reasoning in it is not lost.

---

# Privacy policy additions — deploy to ourmynd.com/privacy

Written for: whoever maintains the ourmynd.com privacy policy. These are the
sections Apple's Guideline 5.1.1(i) / 5.1.2(i) rejection requires. Add or merge
them into the existing policy, then bump its "last updated" date. The in-app AI
disclosure the app now shows is dated 2026-11-22; the policy should not predate
it.

Do not invent claims about Groq's own data handling. The text below says only
what we control and points readers to Groq's own policy for the rest. Before
publishing, confirm the Groq data-processing terms linked still stand.

---

## Who we are (data controller)

OurMynd is operated by **[registered company name]**, whose registered office
is:

> 2nd Floor, 112 High Road, Ilford, England, IG1 1BY

We are the controller of the personal data described in this policy. You can
reach us about privacy at **support@ourmynd.com**.

> Note: fill in the exact registered company name as it appears on the
> incorporation record. The address is set; the legal name is the one field I
> could not supply.

---

## The AI coach and a third-party AI provider

The coach is powered by a third-party AI provider, **Groq, Inc.**, a US-based
AI inference service. The coach does not run on your device: to generate each
reply, we send your request to Groq and return its response to you.

**What is sent.** When you send a message to the coach, we transmit to Groq:

- the content of the message you typed, and the recent messages in that
  conversation needed for the reply to make sense;
- the coaching style you have selected;
- **only if you have separately agreed to this on the Health data screen**,
  context drawn from your mood check-ins and the memory the coach keeps about
  you. If you have not agreed to that, none of it is sent.

**What is not sent.** We do not send Groq your email address, your sign-in
identity, your tasks, goals, habits, notes, or any payment information.

**Why.** Solely to generate the coach's reply to you. We do not use the content
of your coach messages for any other purpose, and we do not sell it.

**Your choice.** We ask for your agreement before the first time anything is
sent to the coach, and the coach does not function until you agree, because
sending your message to the provider is how it replies. You can withdraw that
agreement at any time in **Settings → Coach & AI**; the coach then stops and
nothing further is sent. The rest of the app is unaffected either way.

**Groq's own handling.** Once your message reaches Groq it is also subject to
Groq's processing as an independent matter. See Groq's privacy policy at
https://groq.com/privacy-policy/ for how they handle data they receive.

---

## If the user connects their own AI account

The app lets people connect their own **Anthropic (Claude)** or **Google
(Gemini)** account. When they do, the coach talks to that provider instead, and
the arrangement changes in ways the policy has to state:

- **Their key never reaches us.** It is stored in the device keychain, and the
  request goes directly from their phone to the provider. We do not hold,
  transmit or have access to that credential.
- **We are not in the path.** Because the request does not pass through our
  servers, we do not see, log or store the content of those conversations at
  all. Their relationship for that processing is with the provider directly,
  under the provider's own terms.
- **What is sent is the same material** described above: the message, the
  recent conversation, the coaching style, and mood/memory context only where
  health-data consent has been given separately.
- **Only the conversation moves.** The rest of the app's AI work (the feed,
  goals, mood, memory and the brain dump) continues to run on our own
  provider, so connecting an account does not silently route other data
  somewhere new.
- Anthropic's privacy policy: https://www.anthropic.com/legal/privacy
- Google's AI Studio / Gemini API terms: https://ai.google.dev/gemini-api/terms

The in-app disclosure names whichever provider is actually in use at the time,
so somebody who has connected Claude is told their data goes to Anthropic, not
to the default provider.

## What this means for the "data collected / shared" summary

If your policy has a table or list enumerating data collected and who it is
shared with (5.1.1(i) requires one), add a row:

| Data | Purpose | Shared with |
|---|---|---|
| Coach messages, and (only with your separate consent) mood and memory context | Generate the AI coach's replies | Groq, Inc. (AI inference provider) |
| The same, when the user has connected their own account | Generate the AI coach's replies | Anthropic, or Google, as chosen by the user (sent directly from their device) |

The same disclosure must be reflected in App Store Connect → App Privacy, under
the data types you collect, with "Third-party advertising / data use" left off
and the AI processing recorded as a use of the relevant data types.
