#' Install Hugo
#'
#' Download the appropriate Hugo executable for your platform from Github and
#' try to copy it to a system directory so \pkg{blogdown} can run the
#' \command{hugo} command to build a site. \code{update_hugo()} is a wrapper of
#' \code{install_hugo(force = TRUE)}.
#'
#' This function tries to install Hugo to \code{Sys.getenv('APPDATA')} on
#' Windows, \file{~/Library/Application Support} on macOS, and \file{~/bin/} on
#' other platforms (such as Linux). If these directories are not writable, the
#' package directory \file{Hugo} of \pkg{blogdown} will be used. If it still
#' fails, you have to install Hugo by yourself and make sure it can be found via
#' the environment variable \code{PATH}.
#'
#' This is just a helper function and may fail to choose the correct Hugo
#' executable for your operating system, especially if you are not on Windows or
#' Mac or a major Linux distribution. When in doubt, read the Hugo documentation
#' and install it by yourself: \url{https://gohugo.io}.
#'
#' If you want to install Hugo to a custom path, you can set the global option
#' \code{blogdown.hugo.dir} to a directory to store the Hugo executable before
#' you call \code{install_hugo()}, e.g., \code{options(blogdown.hugo.dir =
#' '~/Downloads/hugo_0.20.1/')}. This may be useful for you to use a specific
#' version of Hugo for a specific website. You can set this option per project.
#' See \href{https://bookdown.org/yihui/blogdown/global-options.html}{Section
#' 1.4 Global options} for details, or store a copy of Hugo on a USB Flash drive
#' along with your website.
#' @param version The Hugo version number, e.g., \code{0.26}; the special value
#'   \code{latest} means the latest version (fetched from Github releases).
#'   Alternatively, this argument can take a file path of the zip archive or
#'   tarball of the Hugo installer that has already been downloaded from Github,
#'   in which case it will not be downloaded again.
#' @param use_brew Whether to use Homebrew (\url{https://brew.sh}) on macOS to
#'   install Hugo (recommended if you have already installed Homebrew). Note
#'   Homebrew will be automatically installed if it has not been installed when
#'   \code{use_brew = TRUE}.
#' @param force Whether to install Hugo even if it has already been installed.
#'   This may be useful when upgrading Hugo (if you use Homebrew, run the
#'   command \command{brew update && brew upgrade} instead).
#' @param extended Whether to use extended version of Hugo that has SCSS/SASS support.
#'   You only need the extended version if you want to edit SCSS/SASS.
#' @export
install_hugo = function(
  version = 'latest', use_brew = Sys.which('brew') != '', force = FALSE, extended = TRUE
) {

  if (Sys.which('hugo') != '' && !force) {
    message('It seems Hugo has been installed. Use force = TRUE to reinstall or upgrade.')
    return(invisible())
  }

  local_file = if (grepl('[.](zip|tar[.]gz)$', version) && file.exists(version))
    normalizePath(version)

  # in theory, should access the Github API using httr/jsonlite but this
  # poor-man's version may work as well
  if (version == 'latest') {
    h = readLines('https://github.com/gohugoio/hugo/releases/latest', warn = FALSE)
    r = '^.*?releases/tag/v([0-9.]+)".*'
    version = gsub(r, '\\1', grep(r, h, value = TRUE)[1])
    message('The latest Hugo version is ', version)
  } else if (use_brew) {
    if (is.null(local_file)) warning(
      "when use_brew = TRUE, only the latest version of Hugo can be installed"
    ) else {
      warning(
        "A local installer was provided through version='", local_file, "', ",
        'so use_brew = TRUE was ignored.'
      )
      use_brew = FALSE
    }
  }

  if (!is.null(local_file)) version = gsub('^hugo_([0-9.]+)_.*', '\\1', basename(local_file))

  version = gsub('^[vV]', '', version)  # pure version number
  version2 = as.numeric_version(version)
  bit = if (is_64bit()) '64bit' else '32bit'
  if (extended) {
    if (bit != '64bit') stop('The extended version of Hugo is only available on 64-bit platforms')
    if (version2 < '0.43') {
      if (!missing(extended)) stop('Only Hugo >= v0.43 provides the extended version')
      extended = FALSE
    }
  }
  base = sprintf('https://github.com/gohugoio/hugo/releases/download/v%s/', version)
  owd = setwd(tempdir())
  on.exit(setwd(owd), add = TRUE)
  unlink(sprintf('hugo_%s*', version), recursive = TRUE)

  download_zip = function(OS, type = 'zip') {
    if (is.null(local_file)) {
      zipfile = sprintf(
        'hugo_%s%s_%s-%s.%s', ifelse(extended, 'extended_', ''), version, OS, bit, type
      )
      xfun::download_file(paste0(base, zipfile), zipfile, mode = 'wb')
    } else {
      zipfile = local_file
      type = xfun::file_ext(local_file)
    }
    switch(type, zip = utils::unzip(zipfile), tar.gz = {
      files = utils::untar(zipfile, list = TRUE)
      utils::untar(zipfile)
      files
    })
  }

  files = if (is_windows()) {
    download_zip('Windows')
  } else if (is_osx()) {
    if (use_brew) {
      if (brew_hugo() == 0) return()
      warning(
        'Failed to use Homebrew to install Hugo. ',
        'I will try to download the Hugo binary directly and install it.'
      )
    }
    download_zip(
      if (version2 >= '0.18') 'macOS' else 'MacOS',
      if (version2 >= '0.20.3') 'tar.gz' else 'zip'
    )
  } else {
    download_zip('Linux', 'tar.gz')  # _might_ be Linux; good luck
  }
  # from a certain version of Hugo, the executable is no longer named
  # hugo_x.y.z, so exec could be NA here, but file.rename(NA_character) is fine
  exec = files[grep(sprintf('^hugo_%s.+', version), basename(files))][1]
  if (is_windows()) {
    file.rename(exec, 'hugo.exe')
    exec = 'hugo.exe'
  } else {
    file.rename(exec, 'hugo')
    exec = 'hugo'
    Sys.chmod(exec, '0755')  # chmod +x
  }

  install_hugo_bin(exec)
}

install_hugo_bin = function(exec) {
  success = FALSE
  dirs = bin_paths()
  for (destdir in dirs) {
    dir.create(destdir, showWarnings = FALSE)
    success = file.copy(exec, destdir, overwrite = TRUE)
    if (success) break
  }
  if (!success) stop(
    'Unable to install Hugo to any of these dirs: ',
    paste(dirs, collapse = ', ')
  )
  message('Hugo has been installed to ', normalizePath(destdir))
}

#' @export
#' @rdname install_hugo
update_hugo = function() install_hugo(
  force = TRUE, use_brew = Sys.which('brew') != '' && !any(dir_exists(bin_paths()))
)

brew_hugo = function() {
  install = function() system('brew update && brew reinstall hugo')
  status = 1  # reinstall Homebrew if `brew install hugo` failed
  if (Sys.which('brew') == '' || (status <- install()) != 0) system2(
    '/usr/bin/ruby',
    '-e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"'
  )
  if (status == 0) status else install()
}

# possible locations of the Hugo executable
bin_paths = function(dir = 'Hugo', extra_path = getOption('blogdown.hugo.dir')) {
  if (is_windows()) {
    path = Sys.getenv('APPDATA', '')
    path = if (dir_exists(path)) file.path(path, dir)
  } else if (is_osx()) {
    path = '~/Library/Application Support'
    path = if (dir_exists(path)) file.path(path, dir)
    path = c('/usr/local/bin', path)
  } else {
    path = c('~/bin', '/snap/bin', '/var/lib/snapd/snap/bin')
  }
  path = c(extra_path, path, pkg_file(dir, mustWork = FALSE))
  path
}

# find an executable from PATH, APPDATA, system.file(), ~/bin, etc
find_exec = function(cmd, dir, info = '') {
  for (d in bin_paths(dir)) {
    exec = if (is_windows()) paste0(cmd, ".exe") else cmd
    path = file.path(d, exec)
    if (utils::file_test("-x", path)) break else path = ''
  }
  path2 = Sys.which(cmd)
  if (path == '' || xfun::same_path(path, path2)) {
    if (path2 == '') stop(cmd, ' not found. ', info, call. = FALSE)
    return(cmd)  # do not use the full path of the command
  } else {
    if (path2 != '') warning(
      'Found ', cmd, ' at "', path, '" and "', path2, '". The former will be used. ',
      "If you don't need both copies, you may delete/uninstall one."
    )
  }
  normalizePath(path)
}

find_hugo = local({
  path = NULL  # cache the path to hugo
  function() {
    if (is.null(path)) path <<- find_exec(
      'hugo', 'Hugo', 'You can install it via blogdown::install_hugo()'
    )
    path
  }
})
