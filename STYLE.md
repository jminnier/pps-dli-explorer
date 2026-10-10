# Writing style (English and Spanish pages)

The site follows the [Federal Plain Language Guidelines](https://digital.gov/guides/plain-language) (Plain Writing Act of 2010). Spanish pages also follow GSA's [Spanish Language Style Guide and Glossaries](https://digital.gov/resources/spanish-language-style-guide-and-glossaries), which the North American Academy of the Spanish Language (ANLE) peer reviewed, and the language-access resources collected by the [U.S. Digital Response Benefits Resource Hub](https://usdr.gitbook.io/benefits-resource-hub/additional-deep-dives/master/what-were-reading/language-access-resources). Spanish terms are in `es/GLOSSARY.md`.

**Readers:** Portland families, many of them Spanish speakers, plus board members, teachers and reporters. Most will read on a phone. Write so that a parent can understand a section after one reading.

**What never changes in a rewrite:** numbers, inline R code, chunk labels, `{#id}` anchors, `cite()` calls, source blocks, links, and direct quotations (English quotes stay word for word; Spanish pages translate them and say so once). Plain language must not drop a caveat or a limit on what the data show. If a sentence is long because it carries a needed qualification, split it; don't cut the qualification.

## Rules from the federal guidelines

**Organize for the reader**
- Put the main point first: in the page, in each section, and in each paragraph.
- Use headings that say what the section tells you. A question or a short statement works ("Families would travel farther"), not a label alone ("Distance").
- One topic per paragraph. Three to eight sentences, at most 150 words; never more than 250.
- Use lists for steps or for three or more parallel items, and tables for numbers that readers compare.
- Use bold sparingly, never underline, and never use all capitals.

**Write clear, short sentences**
- One idea per sentence. Aim for an average of 15 to 20 words. Split any sentence over 30 words, except a direct quotation.
- Use active voice and name the actor: "PPS would move the program", not "the program would be moved".
- Use the present tense when you can. Use "would" for what the scenarios propose.
- Use verbs, not hidden verbs: "PPS projects", not "PPS's projection is that"; "compare", not "make a comparison".
- Use positive language. Avoid double negatives ("at least", not "no fewer than").
- Address the reader as "you" where the text speaks to families.

**Choose familiar words**
- Prefer short, everyday words: use, start, help, about, so, if, now, to (not utilize, commence, assist, approximately, in order that, in the event of, at this point in time, in order to).
- Explain a technical term the first time you use it on a page (capture rate, strand, functional capacity, standard deviation, margin of error).
- Keep the same term for the same thing throughout the site. Don't switch between synonyms for variety.
- Limit abbreviations. DLI, PPS, PSU, K-5 and ODE are fine after they are spelled out once per page. Spell out the rest, or use a short name ("the audit", "the forecast").
- Write "for example" and "that is", not "e.g." and "i.e.". Don't use "and/or" or a slash between words.
- Avoid noun strings: "the plan to move the Spanish program", not "the Spanish program relocation plan".

**Test**
- Run `python3 tools/readability.py` after editing. Targets for body text: English Flesch-Kincaid grade 9 or lower; Spanish Fernández-Huerta 70 or higher; fewer than 10% of sentences over 25 words. Use `--long 5` to find the sentences to split. The score is a rough guide; reading the page aloud is the better test.
- Plain-language testing means asking real readers. Before calling a Spanish page final, a native Spanish speaker from the community should review it (see `es/GLOSSARY.md`, "Terms to review").

## Spanish pages

These come from the GSA Spanish style guide and the language-access resources listed above.

- **Adapt, don't translate word for word.** Write the idea as a Spanish speaker would say it. Spanish sentences run longer than English ones; split them rather than copying the English structure. The same plain-language rules apply.
- **Neutral Latin American Spanish, usted.** No Spain-only words (vosotros, ordenador, coger).
- **Capitalization:** titles and headings in sentence case ("Equidad: a quién afectan los cambios", not "Equidad: A Quién Afectan Los Cambios"). Lowercase days, months, languages and nationalities (martes, octubre, español, japonés), unless they start a sentence.
- **Dates:** "6 de octubre de 2026". School years stay as 2025-26.
- **Numbers:** U.S. notation, as GSA/ANLE recommend for Spanish published in the United States: 1,586 and 0.8 (not 1.586 or 0,8). Ordinals: 5.º grado.
- **Abbreviations:** EE. UU. (with periods and a space). Acronyms take no periods (PPS, DLI). Explain an English acronym the first time it appears: "DLI (inmersión en dos idiomas)".
- **Punctuation:** opening ¿ and ¡. Periods and commas go outside closing quotation marks and parentheses.
- **Frequently mistranslated terms (GSA):**
  - application → solicitud (not aplicación); apply for → solicitar (not aplicar)
  - "applies to" → se aplica a, or rephrase ("es para")
  - qualify → reunir los requisitos (not calificar)
  - American → estadounidense (not americano)
  - submit → enviar, presentar (not someter); access → acceder a (not accesar)
  - requirement → requisito; guidelines → pautas, directrices
  - comprehensive → completo, amplio (not comprensivo); directions → indicaciones (not direcciones)
  - fact sheet → hoja informativa; form → formulario
- **Inclusive language:** following the (Re)Nombrar guide, prefer collective or neutral nouns where they read naturally: las familias, el personal docente, el estudiantado, quienes solicitan. Keep a source's own term inside a quotation, for example the audit's "latinos/as/x". Use "latino" or "latina" in the site's own prose, matching the group described.
- **Reference dictionary:** Real Academia Española, <https://dle.rae.es/>.
