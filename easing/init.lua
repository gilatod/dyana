local folder = (...):gsub("%.init$", "")
return require(folder..".easing")