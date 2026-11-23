# Privacy policy — replacement for Section 4

**Paste target:** `ourmynd.com/privacy`, section **"4. AI Processing and Third-Party AI Providers"**.
Replace that section wholesale with the text under "Replacement text" below.

Everything else on the live page stays as it is. Section 1 (The Social Globe
Ltd, company 13923693, registered office, UK GDPR controller statement) is
already correct and needs no change.

---

## Why this has to change

The live section says messages go to **"Anthropic and OpenAI"**. Checked
against the code, that is wrong in three ways, and the second one is the kind
of thing App Review opens a rejection with.

| provider | actually receives data | named in the live policy |
|---|---|---|
| **Groq, Inc.** | yes — every coach reply, and all voice-note audio | **no** |
| **Puter** | only if the user connects their own account | no |
| **Anthropic** | only via Puter, if connected | yes |
| **Google** | only via Puter (Gemini), if connected | no |
| **OpenAI** | **never** | yes |

**Where the OpenAI error almost certainly came from:** the server calls
`https://api.groq.com/openai/v1/chat/completions` and
`https://api.groq.com/openai/v1/audio/transcriptions`. The `/openai/` in the
path is Groq advertising an OpenAI-*compatible* API. The host is Groq. Nothing
is sent to OpenAI.

The third gap: **audio is not mentioned at all.** Voice notes are uploaded and
transcribed by Groq (`whisper-large-v3-turbo`). Audio is a separate data
category, it is declared in the app's `PrivacyInfo.xcprivacy`, and Apple's
letter asks specifically that the policy "identify what data the app collects".

---

## Replacement text

> ### 4. AI processing and third-party AI providers
>
> The coach does not run on your phone. To write a reply, what you send has to
> be transmitted to an AI provider outside OurMynd. This section says exactly
> what is sent, to whom, and what they may do with it.
>
> **We ask before any of it happens.** The first time you open the coach, the
> app shows you a disclosure naming the provider and asks you to agree. Nothing
> is sent to any AI provider until you do. You can withdraw at any time in
> Settings, after which the coach stops working and nothing further is sent.
> Declining affects only the coach; the rest of the app is unchanged.
>
> #### What is sent
>
> * **The messages you type to the coach.**
> * **The context the coach is given to answer with** — the relevant parts of
>   your goals, tasks, routines and saved memory.
> * **Your mood and memory entries, only if you have separately agreed to that.**
>   Health-related context is governed by its own, separate permission. If you
>   decline it, the coach still works and that context is not included.
> * **Voice-note audio, if you record one.** Voice notes are uploaded and
>   converted to text so the coach can read them.
>
> We do not send your email address, your name, your payment details or your
> location to any AI provider.
>
> #### Who it is sent to
>
> **Groq, Inc.** (United States) is the default provider and handles both
> coaching replies and voice-note transcription. Unless you have connected your
> own account with another provider, Groq is the only AI provider that receives
> your data.
>
> **If you choose to connect your own AI account**, the app can instead route
> your messages through **Puter**, which passes them to the model you pick:
>
> * **Anthropic** (Claude models)
> * **Google** (Gemini models)
>
> This is off by default. It happens only if you connect an account yourself,
> and the app names the provider on screen and asks you again before switching,
> because agreeing to one recipient is not agreeing to another.
>
> We do not send your data to OpenAI.
>
> #### What they may do with it
>
> These providers act as our processors. They may use your data only to produce
> the response they return to us, and only on our instructions. They may not use
> it for their own purposes.
>
> **Your conversations are not used to train AI models.** Our agreements with
> these providers prohibit the use of data submitted through their business
> interfaces to train or improve their models.
>
> Your data is encrypted in transit. Providers may retain content briefly for
> abuse monitoring where their own legal obligations require it, and then delete
> it. These providers are in the United States; transfers are made under the UK
> International Data Transfer Addendum and the EU Standard Contractual Clauses,
> and we have satisfied ourselves that they offer protection equivalent to that
> required under UK and EU data protection law.
>
> If we change AI provider, we will update this policy before the change takes
> effect, and the app will ask for your agreement again before sending anything
> to the new one.
>
> OurMynd is a coaching and productivity tool and is not a medical device,
> therapist, or crisis service. Please see our Terms & Conditions.

---

## Two claims to verify before you publish

I have kept these from your existing text because they are probably true, but
they are statements about other companies' contracts and I cannot verify them
from this repo. **Check both, and cut or reword anything you cannot evidence** —
an unverifiable claim in a privacy policy is worse than a narrower one.

1. **"not used to train"** — confirm against Groq's current API terms and DPA,
   and that you have actually accepted them on the account whose key the server
   uses. Groq's published API terms do say this; make sure your account is on
   those terms and not a consumer tier.
2. **The transfer mechanism** — confirm you have an executed DPA with Groq
   incorporating the UK IDTA / EU SCCs. If you have not, say instead that
   transfers are made under the provider's standard terms and remove the
   equivalence claim until the DPA is signed.

## Also update, so the three agree

* **App Store Connect → App Privacy** must match
  `ios/Runner/PrivacyInfo.xcprivacy` and this section. See
  `appreview/asc-privacy-answers.md`.
* The in-app disclosure already names the active provider at runtime
  (`AiRouter.activeCompany`), so it is correct for all four routes without
  further edits.
