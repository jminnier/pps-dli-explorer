# Rumores y hechos / Rumors & Facts: content for atkinsondli.org

Prepared Nov 5, 2026 by the Keep DLI at Atkinson campaign. This file is a brief plus all the content for a new bilingual web page. It is the web version of the Instagram carousel posted Nov 5, 2026 (`handouts/atkinson_rumores_hechos.zip`).

---

## Instructions for Claude Code

1. **Read the site first.** Look at how existing pages are built (for example /commute, /survey, /act), including how Spanish and English versions are handled (`?lang=en`, separate pages or a toggle), the shared layout, the nav and the footer. Match those patterns. Don't invent a new system.
2. **Add a page** at `/facts` (or `/hechos`; use the site's existing slug style), titled "Rumores y hechos" (ES) / "Rumors & Facts" (EN). Spanish is the default language, as on the rest of the site. Add it to the nav and the sitemap if the site has them.
3. **Use the brand.** Follow the site's existing tokens, or the brand guide at /brand:
   - Colors: cheetah blue #173B85, gold #F2A518, burnt orange #B8420F, ink #1D2433, cream #FFFAF2, sand #FDF1E1.
   - Fonts: Fraunces 800/600 for headings; Atkinson Hyperlegible 400/700 for body text.
   - Never put gold text on orange.
4. **Suggested layout:**
   - Intro (section A).
   - "What PPS left out" comparison table (section B). On phones, collapse it to stacked cards: one card per row, each showing "PPS's slide said" and then "Atkinson today."
   - Rumor/fact cards (section C):
     - The rumor goes in a muted gray card with a rotated stamp: FALSO / FALSE, MEDIA VERDAD / HALF TRUE, or NO.
     - The fact goes in a blue card below it, with a big gold number.
     - For item C2, add a simple horizontal bar chart of Lent's building use. Use HTML/CSS or the site's chart library. Include a dashed capacity line and text labels; don't use color alone to carry meaning.
   - Closing call to action (section D) with a button to /act.
   - Sources and methods in a collapsible section at the end (section E).
5. **Keep every source line and caveat.** Each card has a short source line; show it as small text under the card. Put the long methods notes in section E.
6. **Accessibility:**
   - Headings in a sensible order.
   - Charts need a text alternative (an `aria-label` or a visually hidden table).
   - Text contrast of 4.5:1 or more.
   - Stamps that are rotated text should still read correctly to screen readers, for example "Rumor: false".
7. **Don't add content** that isn't in this file. If something is ambiguous, leave a TODO comment rather than guessing. Don't name staff members, board members or parents.
8. Optionally, put the structured data from section F in a JSON or YAML data file and render the page from it. That makes it easier to update when PPS changes its plan on Nov 17.

---

## A. Intro / hero

**ES**
- Etiqueta: Junta de PPS · 4 nov. 2026
- Título: Tomemos una página del libro de PPS: rumores y hechos
- Texto: PPS tiene su propia página de "rumores y hechos". Aquí están los nuestros, de Atkinson: una escuela DLI **y** de vecindario.
- Contexto: En la junta del 4 de noviembre, PPS mostró una diapositiva llamada "Student Journey: Atkinson to Lent" (el recorrido de un estudiante de Atkinson a Lent). Dejó fuera mucho de lo que hace funcionar a nuestra escuela.

**EN**
- Label: PPS Board · Nov 4, 2026
- Title: Let's take a page out of PPS's book: rumors & facts
- Text: PPS has its own "rumors and facts" page. Here are ours, from Atkinson: a DLI **and** neighborhood school.
- Context: At the Nov 4 board meeting, PPS showed a slide called "Student Journey: Atkinson to Lent." It left out a lot of what makes our school work.

---

## B. What PPS left out / Lo que PPS no mostró

Section title. ES: La diapositiva de PPS sobre Atkinson dejó fuera mucho. EN: PPS's "Atkinson to Lent" slide left a lot out.

Column headers. ES: Lo que mostró PPS | Atkinson hoy. EN: PPS's slide said | Atkinson today.

| Topic (ES / EN) | PPS's slide said (ES / EN) | Atkinson today (ES / EN) |
|---|---|---|
| Comunidad DLI / DLI community | Programa DLI de una sola clase por grado. / Single-strand DLI program. | Programa DLI desde 1994. Maestros y familias de varias generaciones. / DLI since 1994. Teachers and families across generations. |
| Idioma / Language environment | Solo la mitad de la escuela aprende español. / Only about half the school learns Spanish. | DLI y vecindario juntos: es parte del modelo, no una falla. / DLI and neighborhood students together: a feature, not a flaw. |
| Maestros / Teacher collaboration | Un solo maestro DLI por grado. / One DLI teacher per grade. | Maestros DLI y de vecindario planean juntos lecciones y eventos culturales. / DLI and neighborhood teachers plan lessons and cultural events together. |
| Enriquecimiento / Enrichment | Arte, Ed. Física y Biblioteca quizás no en español. / Arts, PE and Library may not be in Spanish. | Las clases en inglés son parte del modelo 90/10 y 80/20. Maestra de huerto bilingüe. / English specials are part of the 90/10, 80/20 model. Bilingual garden teacher. |
| Apoyo / Student support | Intervención académica solo en inglés. / Academic intervention in English only. | Bilingües: especialista de habla y lectura, tutor HIT, asistentes, psicóloga, directora, oficina y maestros de ELD, 1.º y 4.º. / Bilingual: speech/reading specialist, HIT tutor, paraeducators, school psychologist, principal, office staff, and ELD and 1st/4th grade teachers. |
| Tamaño de clase / Class size | 1.º en Atkinson: 28 por clase. 2.º en Lent: 24 por clase. / 1st grade at Atkinson: 28 per class. 2nd at Lent: 24 per class. | 1.º hoy: 27. Los 24 por clase en Lent suponen que los 27 se mudan: (27 + 46 de Lent) ÷ 3 clases. / 1st grade today: 27. Lent's 24 per class assumes all 27 move: (27 + 46 Lent students) ÷ 3 classes. |

Source line. ES: Diapositiva "Student Journey: Atkinson to Lent", junta de PPS, 4 nov. 2026; personal y matrícula de Atkinson. Adaptado de una tabla hecha por una familia de Atkinson. EN: PPS slide "Student Journey: Atkinson to Lent," Nov 4, 2026 board meeting; Atkinson staffing and enrollment. Adapted from a chart made by an Atkinson parent.

---

## C. Rumors & facts / Rumores y hechos

### C1. Who is in DLI

- **Stamp:** FALSO / FALSE
- **Rumor:** ES: "El DLI es para familias privilegiadas o que no hablan español." EN: "DLI is mostly for privileged families or non-native speakers."
- **Fact, big numbers:** **71%** and **40%**
  - ES: 71% de los estudiantes DLI de Atkinson son de grupos históricamente desatendidos. 40% son estudiantes multilingües (MLL). El DLI es casi la mitad de la escuela: 178 de 366 estudiantes.
  - EN: 71% of Atkinson DLI students are historically underserved. 40% are multilingual learners. DLI is almost half of the school: 178 of 366 students.
- **Source:** ES: datos de Atkinson, octubre 2025. EN: Atkinson school data, October 2025.

### C2. Families will follow DLI to Lent

- **Stamp:** FALSO / FALSE
- **Rumor:** ES: "Las familias seguirán al programa a Lent." EN: "Families will follow DLI to Lent."
- **Fact, big numbers:** **63%** and **70%**
  - ES: 63% de las familias DLI dicen que probablemente o definitivamente no continuarían. 70% de las familias hispanohablantes dicen lo mismo.
  - EN: 63% of DLI families say they probably or definitely wouldn't continue. 70% of Spanish-speaking families say the same.
- **Chart heading:** ES: Si las familias hacen lo que dicen, Lent seguiría a menos de 40% de su capacidad. EN: If families do what they say, Lent stays under 40% full.
- **Chart: Lent's building, capacity 798**

  | Bar (ES / EN) | Students | % of capacity |
  |---|---|---|
  | Lent hoy / Lent today | 256 | 32% |
  | Proyección de PPS / PPS projection, 2027 | 401 | 50% |
  | Según la encuesta / Per our survey | ~283–303 | 35–38% |

- **Source:** Atkinson family survey, Oct 2026 (independent, parent-led, not representative; 109 responses; 42 of 67 DLI families; 30 of 43 native or heritage Spanish-speaking families). Lent enrollment and capacity: PPS school profile 2025. Projection: PPS Scenario A, 2027.
  - The survey range is 256 plus 15% of Atkinson's 178 DLI students (families who would continue), up to 256 plus that 15% and half of the 22% who were unsure.
  - PPS's plan table shows 434 (54%) if all 178 students move.

### C3. Attendance

- **Stamp:** FALSO / FALSE
- **Rumor:** ES: "Juntar el DLI en Lent va a mejorar la asistencia." EN: "Consolidating DLI at Lent will improve attendance."
- **Fact:** ES: Atkinson ya está en la meta de asistencia que Lent espera alcanzar en 2027. EN: Atkinson is already at the attendance goal Lent hopes to reach by 2027.

  | School | Today | 2027 goal |
  |---|---|---|
  | Atkinson | 80% | 83% |
  | Lent | 76% | 80% |

- **Takeaway:** ES: Viajes más largos no mejoran la asistencia. La hacen más difícil. EN: Longer commutes don't raise attendance. They make it harder. *(This is our framing, not a statistic. It could link to /commute.)*
- **Source:** Share of students with good or acceptable attendance. School Continuous Improvement Plans (SCIP) 2025–26 for Atkinson and Lent, access.pps.net/our-school/school-continuous-improvement-plan-scip

### C4. Lent is near where Spanish speakers live

- **Stamp:** MEDIA VERDAD / HALF TRUE
- **Rumor:** ES: "Lent está cerca de donde vive la gente que habla español." EN: "Lent is near where Spanish speakers live."
- **Fact, big numbers:** **6 de 10 / 6 in 10** and **28%**
  - ES: 6 de 10 niños hispanohablantes a 2 millas de Lent viven fuera del distrito de PPS. Solo el 28% de los niños de PPS en la zona de Lent van a Lent (80 de 286).
  - EN: About 6 in 10 Spanish-speaking kids within 2 miles of Lent live outside PPS. Only 28% of PPS kids in Lent's own zone attend Lent (80 of 286).
- **More:**
  - ES: Si muchas familias latinas cerca de Lent quisieran DLI en toda la escuela, se vería en las solicitudes cada año. Y en todo el sureste hay familias hispanohablantes que no pueden llegar a Lent dos veces al día.
  - EN: If many Latino families near Lent wanted whole-school DLI, yearly applications would show it. And Spanish-speaking families across Southeast Portland can't get to Lent twice a day.
- **Source:** U.S. Census, ACS 2020–24 table B16007 (Spanish spoken at home, ages 5–17), allocated to blocks; about 1,380 children, about 830 outside PPS, with wide margins of error. Lent zone: PPS school profile 2025. See methods in section E.

### C5. Consolidate to support Chávez and Lent

- **Stamp:** NO
- **Rumor:** ES: "Hay que juntar el DLI para apoyar a César Chávez y a Lent." EN: "We have to consolidate DLI to support César Chávez and Lent."
- **Our view** (label "NUESTRA PROPUESTA · OUR VIEW", not "FACT"; use an orange card):
  - ES: Financien a Chávez y a Lent. Dejen en paz a las escuelas que funcionan.
  - EN: Fund Chávez and Lent so they thrive. Leave working neighborhood schools alone.
- **Note:**
  - ES: Nadie aquí está en contra de Lent. Queremos que todas las escuelas DLI del sureste tengan éxito.
  - EN: No one here is against Lent. We want every Southeast DLI school to succeed.

---

## D. Closing / call to action

- ES: **PPS tiene sus hechos. Estos son los nuestros.** La superintendente da su recomendación el 17 de noviembre. Pida a la junta y a sus legisladores que escuchen a las familias DLI. Botón: "Actúe" → /act. ¡No nos vamos!
- EN: **PPS has its facts. These are ours.** The superintendent's recommendation comes Nov 17. Ask the board and your legislators to listen to DLI families. Button: "Take action" → /act. We're not leaving!

---

## E. Sources & methods (collapsible "Fuentes y métodos / Sources & methods")

1. **PPS slide.** "Student Journey: Atkinson to Lent," shown at the PPS Board of Education regular meeting, Nov 4, 2026, at 3:51:12 of the recording (youtube.com/watch?v=9kX3vnfRlvY). The narration said Lent would offer "a whole school immersive experience" and that supports "could be in the native language."
2. **Atkinson data.** Atkinson school data (October 2025): 366 students, of whom 44% are historically underserved and 21% are multilingual learners. DLI has 178 students (49% of the school), of whom 71% are historically underserved and 40% are multilingual learners. Staffing roles come from the Atkinson community fact sheet "Correcting data presented to the Board," Nov 4, 2026.
3. **Family survey.** Atkinson family survey (final, Oct 26, 2026; atkinsondli.org/survey). Independent, anonymous and parent-led. Not representative, not an official PPS study. Answers are stated intentions, not decisions.
   - 109 responses.
   - Of 67 DLI families: 63% (42) wouldn't continue, 22% unsure, 15% would continue.
   - Of 43 native or heritage Spanish-speaking families: 70% (30) wouldn't continue.
4. **Lent building.** PPS school profile 2025: Lent has 256 students and a functional capacity of 798. 80 of the 286 PPS students living in Lent's attendance zone attend Lent. The PPS Scenario A 2027 projection is 401. All of these are as compiled in the pps_explorer_dli_2026 repo.
5. **Attendance goals.** From the 2025–26 SCIPs on access.pps.net. Atkinson: "from 80% to 83%" by June 2027. Lent: "from 76% to 80%" by June 2027.
6. **Census method.**
   - Data: ACS 5-year 2020–2024, table B16007 (age 5–17, speaks Spanish at home), for every census tract in Multnomah, Washington and Clackamas counties.
   - Allocation: each tract's count was spread to its 2020 census blocks by the block's share of the tract's under-18 population (2020 decennial P1 minus P3).
   - Distance: blocks whose interior point lies within 2 miles (straight line) of Lent (45.4853, −122.5642) were kept.
   - Split: blocks were classed as inside or outside the PPS boundary (union of the district attendance areas).
   - Result: about 1,380 children; about 550 inside PPS and about 830 (60%) outside, nearly all in east Multnomah County districts. The all-ages share outside is 57%. For comparison, 99% of children within 2 miles of Atkinson live inside PPS.
   - Margin of error: about ±560 on the tracts involved, so the page says "about 6 in 10."
7. **Class size.** 27 Atkinson 1st graders plus 46 Lent 1st graders = 73, divided by 3 classrooms ≈ 24.3. This comes from the parent-made chart; confirm the 46 if possible.

---

## F. Structured data (optional; for a data file)

```json
{
  "page": {
    "slug": "facts",
    "updated": "2026-11-05",
    "title": {"es": "Rumores y hechos", "en": "Rumors & Facts"}
  },
  "comparison": [
    {"topic": {"es": "Comunidad DLI", "en": "DLI community"},
     "pps": {"es": "Programa DLI de una sola clase por grado.", "en": "Single-strand DLI program."},
     "atkinson": {"es": "Programa DLI desde 1994. Maestros y familias de varias generaciones.", "en": "DLI since 1994. Teachers and families across generations."}},
    {"topic": {"es": "Idioma", "en": "Language environment"},
     "pps": {"es": "Solo la mitad de la escuela aprende español.", "en": "Only about half the school learns Spanish."},
     "atkinson": {"es": "DLI y vecindario juntos: es parte del modelo, no una falla.", "en": "DLI and neighborhood students together: a feature, not a flaw."}},
    {"topic": {"es": "Maestros", "en": "Teacher collaboration"},
     "pps": {"es": "Un solo maestro DLI por grado.", "en": "One DLI teacher per grade."},
     "atkinson": {"es": "Maestros DLI y de vecindario planean juntos lecciones y eventos culturales.", "en": "DLI and neighborhood teachers plan lessons and cultural events together."}},
    {"topic": {"es": "Enriquecimiento", "en": "Enrichment"},
     "pps": {"es": "Arte, Ed. Física y Biblioteca quizás no en español.", "en": "Arts, PE and Library may not be in Spanish."},
     "atkinson": {"es": "Las clases en inglés son parte del modelo 90/10 y 80/20. Maestra de huerto bilingüe.", "en": "English specials are part of the 90/10, 80/20 model. Bilingual garden teacher."}},
    {"topic": {"es": "Apoyo", "en": "Student support"},
     "pps": {"es": "Intervención académica solo en inglés.", "en": "Academic intervention in English only."},
     "atkinson": {"es": "Bilingües: especialista de habla y lectura, tutor HIT, asistentes, psicóloga, directora, oficina y maestros de ELD, 1.º y 4.º.", "en": "Bilingual: speech/reading specialist, HIT tutor, paraeducators, school psychologist, principal, office staff, and ELD and 1st/4th grade teachers."}},
    {"topic": {"es": "Tamaño de clase", "en": "Class size"},
     "pps": {"es": "1.º en Atkinson: 28 por clase. 2.º en Lent: 24 por clase.", "en": "1st grade at Atkinson: 28 per class. 2nd at Lent: 24 per class."},
     "atkinson": {"es": "1.º hoy: 27. Los 24 por clase en Lent suponen que los 27 se mudan: (27 + 46 de Lent) ÷ 3 clases.", "en": "1st grade today: 27. Lent's 24 per class assumes all 27 move: (27 + 46 Lent students) ÷ 3 classes."}}
  ],
  "items": [
    {"id": "who", "stamp": "false",
     "rumor": {"es": "El DLI es para familias privilegiadas o que no hablan español.", "en": "DLI is mostly for privileged families or non-native speakers."},
     "stats": [
       {"value": "71%", "es": "de los estudiantes DLI de Atkinson son de grupos históricamente desatendidos", "en": "of Atkinson DLI students are historically underserved"},
       {"value": "40%", "es": "son estudiantes multilingües (MLL)", "en": "are multilingual learners"}],
     "note": {"es": "El DLI es casi la mitad de la escuela: 178 de 366 estudiantes.", "en": "DLI is almost half of the school: 178 of 366 students."},
     "source": "Atkinson school data, October 2025"},
    {"id": "follow", "stamp": "false",
     "rumor": {"es": "Las familias seguirán al programa a Lent.", "en": "Families will follow DLI to Lent."},
     "stats": [
       {"value": "63%", "es": "de las familias DLI dicen que probablemente o definitivamente no continuarían", "en": "of DLI families say they probably or definitely wouldn't continue", "n": "42 of 67"},
       {"value": "70%", "es": "de las familias hispanohablantes dicen lo mismo", "en": "of Spanish-speaking families say the same", "n": "30 of 43"}],
     "chart": {"title": {"es": "Si las familias hacen lo que dicen, Lent seguiría a menos de 40% de su capacidad.", "en": "If families do what they say, Lent stays under 40% full."},
       "capacity": 798,
       "bars": [
         {"label": {"es": "Lent hoy", "en": "Lent today"}, "students": 256, "pct": 32},
         {"label": {"es": "Proyección de PPS (2027)", "en": "PPS projection (2027)"}, "students": 401, "pct": 50},
         {"label": {"es": "Según la encuesta", "en": "Per our survey"}, "students_low": 283, "students_high": 303, "pct_low": 35, "pct_high": 38}]},
     "source": "Atkinson family survey, Oct 2026 (independent, not representative); PPS school profile 2025; PPS Scenario A"},
    {"id": "attendance", "stamp": "false",
     "rumor": {"es": "Juntar el DLI en Lent va a mejorar la asistencia.", "en": "Consolidating DLI at Lent will improve attendance."},
     "fact": {"es": "Atkinson ya está en la meta de asistencia que Lent espera alcanzar en 2027.", "en": "Atkinson is already at the attendance goal Lent hopes to reach by 2027."},
     "table": [
       {"school": "Atkinson", "today": 80, "goal_2027": 83},
       {"school": "Lent", "today": 76, "goal_2027": 80}],
     "takeaway": {"es": "Viajes más largos no mejoran la asistencia. La hacen más difícil.", "en": "Longer commutes don't raise attendance. They make it harder."},
     "source": "SCIP 2025–26, Atkinson and Lent, access.pps.net"},
    {"id": "near", "stamp": "half_true",
     "rumor": {"es": "Lent está cerca de donde vive la gente que habla español.", "en": "Lent is near where Spanish speakers live."},
     "stats": [
       {"value": {"es": "6 de 10", "en": "6 in 10"}, "es": "niños hispanohablantes a 2 millas de Lent viven fuera del distrito de PPS", "en": "Spanish-speaking kids within 2 miles of Lent live outside PPS"},
       {"value": "28%", "es": "de los niños de PPS en la zona de Lent van a Lent (80 de 286)", "en": "of PPS kids in Lent's own zone attend Lent (80 of 286)"}],
     "note": {"es": "Si muchas familias latinas cerca de Lent quisieran DLI en toda la escuela, se vería en las solicitudes cada año. Y en todo el sureste hay familias hispanohablantes que no pueden llegar a Lent dos veces al día.", "en": "If many Latino families near Lent wanted whole-school DLI, yearly applications would show it. And Spanish-speaking families across Southeast Portland can't get to Lent twice a day."},
     "source": "ACS 2020–24 B16007, block-allocated (see methods); PPS school profile 2025"},
    {"id": "consolidate", "stamp": "no", "kind": "our_view",
     "rumor": {"es": "Hay que juntar el DLI para apoyar a César Chávez y a Lent.", "en": "We have to consolidate DLI to support César Chávez and Lent."},
     "view": {"es": "Financien a Chávez y a Lent. Dejen en paz a las escuelas que funcionan.", "en": "Fund Chávez and Lent so they thrive. Leave working neighborhood schools alone."},
     "note": {"es": "Nadie aquí está en contra de Lent. Queremos que todas las escuelas DLI del sureste tengan éxito.", "en": "No one here is against Lent. We want every Southeast DLI school to succeed."}}
  ],
  "cta": {"title": {"es": "PPS tiene sus hechos. Estos son los nuestros.", "en": "PPS has its facts. These are ours."},
          "text": {"es": "La superintendente da su recomendación el 17 de noviembre. Pida a la junta y a sus legisladores que escuchen a las familias DLI.", "en": "The superintendent's recommendation comes Nov 17. Ask the board and your legislators to listen to DLI families."},
          "button": {"es": "Actúe", "en": "Take action", "href": "/act"}}
}
```

---

## G. Before publishing (for the campaign team)

- Confirm the parent who made the comparison chart is OK with the credit "Adapted from a chart made by an Atkinson parent."
- Confirm the 46 Lent 1st graders used in the class-size math.
- "Longer commutes make attendance harder" is our framing, not a sourced statistic. Keep it, link it to /commute, or cut it.
- Update the page after the superintendent's Nov 17 recommendation if the plan for Atkinson changes.
