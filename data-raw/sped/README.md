# Special education programs in the rightsizing scenarios

## `sped_allocation_2026_27_raw.csv`

- **What:** the "SPED" tab of the Google Sheet *Board Request as of 9/22*
  (https://docs.google.com/spreadsheets/d/15yL3mcAjWEHfSQQExKglYJmgfJBNhj_07rM3MrmxEvM), headed "2026-27 Projected Allocation".
- **Where it came from:** PPS board member Virginia La Forte requested the data and shared the sheet on her Facebook account, with this post: “I wanted to see a basic lay of the land and requested this data: How many students and how many sections are there in every grade band at every school including blends? What does staffing look like? What does every individual middle school offer? How many students are in each of those classes? For the data-inclined, see link in comments.” The link was in the comments. It was also shared in the PPS Community Advocacy group. The sheet itself doesn't name who prepared it, and its Readme tab links to a Google Doc that isn't public. It is data a board member requested, not a report PPS has published.
- **Retrieved:** October 11, 2026, with an anonymous CSV export (`gviz/tq?tqx=out:csv&sheet=SPED`). The link opens without signing in.
- **What it counts:** **staff positions, not students.** Each value is a planned 2026-27 allocation for one school (73 K-8, middle and alternative schools; no high schools).
- **Columns, as headed in the sheet:**
  - `26-27 Allocated LC FTE K-8 1:30 HS 1:32`: Learning Center teacher FTE.
  - `SES`, `CB`, `ISC`: teacher positions in Social Emotional Skills, Communication Behavior and Intensive Skills classrooms.
  - `SES Paras`, `CB Paras`, `ISC Paras`: paraeducators (aides) for those classrooms. Most SES, CB and ISC positions come with 3 aides each (a few have 2 or 2.5).
  - `1-1 Para`: one-to-one aides.
  - `QMHP` (Qualified Mental Health Professional) and `TIC` (Therapeutic Instructional Coach): PPS lists both as SES classroom staff on its [service delivery page](https://www.pps.net/fs/pages/22389). `NSM Building Para` isn't defined. The site uses none of these three.
- **PPS's own description** of each classroom (same page): one special education teacher and 2–3 aides, "Student Number: 10-12".
- **Known gap:** the Deaf and Hard of Hearing program at Creston isn't in the sheet. Columbia Regional Inclusive Services (CRIS) runs it.
- **Renames in `sped_programs.R`:** "Lee" is now Sunrise. ACCESS Academy isn't in the plan tables.

## `sped_moves.csv`

Hand-entered. There is one row for each special education program that PPS's school guides (*How Could Your School Be Impacted?*, October 8, 2026) say would move or stay, with the guide's own sentence (page 3).

- **scenario:** `ab` means both scenarios. Lewis and Stephenson close only in Scenario A.
- **status:** `named` means the guide names one new site. `split` means the guide names two possible sites (Sabin SES: Vernon or MLK Jr.). `stays` means the program stays where it is.
- The guides say individual placements are decided with each family. Every guide's page 1 says: "A school or program move does not determine where an individual student receiving special education services will go."

`Rscript data-raw/sped_programs.R` checks that every school in the sheet matches `plan_schools.csv`. It also checks that every closing school with an SES, CB or ISC position has a row here. Its outputs are `data/sped_allocation_2026_27.csv` and `data/sped_moves.csv`.
