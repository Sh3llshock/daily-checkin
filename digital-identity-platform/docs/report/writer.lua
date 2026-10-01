-- Renders ::: writer divs (sections a team member still has to write) as a box.
function Div(el)
  if el.classes:includes("writer") then
    return {
      pandoc.RawBlock("latex", "\\begin{writerbox}"),
      el,
      pandoc.RawBlock("latex", "\\end{writerbox}"),
    }
  end
end
