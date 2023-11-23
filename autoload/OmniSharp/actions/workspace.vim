let s:save_cpo = &cpoptions
set cpoptions&vim

let s:attempts = 0

function! OmniSharp#actions#workspace#Get(job) abort
  let opts = {
  \ 'ResponseHandler': function('s:ProjectsRH', [a:job])
  \}
  let s:attempts += 1
  call OmniSharp#stdio#RequestGlobal(a:job, '/projects', opts)
endfunction

function! s:ProjectsRH(job, response) abort
  " If this request fails, retry up to 5 times
  if !a:response.Success
    if s:attempts < 5
      call OmniSharp#actions#workspace#Get(a:job)
    endif
    return
  endif
  " If no projects have been loaded by the time this callback is reached, there
  " are no projects and the job can be marked as ready
  let projects = get(get(a:response.Body, 'MsBuild', {}), 'Projects', {})
  let a:job.projects = map(projects,
  \ {_,project -> {"name": project.AssemblyName, "path": project.Path, "target": project.TargetPath}})
  if get(a:job, 'projects_total', 0) > 0
    call OmniSharp#log#Log(a:job, 'Workspace complete: ' . a:job.projects_total . ' project(s)')
  else
    call OmniSharp#log#Log(a:job, 'Workspace complete: no projects')
    call OmniSharp#project#RegisterLoaded(a:job)
  endif
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

function! OmniSharp#actions#workspace#GetSolutionPath() abort
  if exists('g:OmniSharp_workspace_root')
    return g:OmniSharp_workspace_root
  endif

  let current_dir = expand('%:p:h')

  " search for *.sln file
  let slnFile = s:search_file_extension(current_dir, ".sln")

  if slnFile != v:null
    let g:OmniSharp_workspace_root = slnFile
    return slnFile
  endif

  " search for *.csproj if there's no sln
  let csprojFile = s:search_file_extension(current_dir, ".csproj")

  if csprojFile == v:null
    throw "Neither the solution nor the project is found"
  endif

  let g:OmniSharp_workspace_root = csprojFile
  return csprojFile
endfunction

function! OmniSharp#actions#workspace#GetExecutableProjectPath() abort
  if !exists('g:OmniSharp_workspace_root')
    call OmniSharp#actions#workspace#GetSolutionPath()
  endif

  " Get all csproj files
  let csprojFiles = globpath(g:OmniSharp_workspace_root, '**/*.csproj', 1, 1)
  let found = 0

  for f in csprojFiles
    let file_content = readfile(f)

    for line in file_content
      if line =~ "Microsoft.NET.Sdk.Web" || line =~ "<OutputType>Exe"
        let found = 1
        let g:Omnisharp_executable_project_path = f
        return f
      endif
    endfor
  endfor

  if found == 0
    throw "Could not find executable project"
  endif
endfunction

function! OmniSharp#actions#workspace#GetExecutableDllPath() abort
  if !exists('g:Omnisharp_executable_project_path')
    call OmniSharp#actions#workspace#GetExecutableProjectPath()
  endif

  " Executable project directory
  let executable_proj_dir = fnamemodify(g:Omnisharp_executable_project_path, ':h')

  let file_name_without_extension = fnamemodify(g:Omnisharp_executable_project_path, ':t:r')
  let dll_name = file_name_without_extension . ".dll"

  let bin_path = executable_proj_dir . '/bin/Debug'
  let dllFiles = globpath(bin_path, "**/" . dll_name, 1, 1)

  if len(dllFiles) == 0
    call OmniSharp#actions#workspace#BuildSolution()
  endif

  let dllFiles = globpath(bin_path, "**/" . dll_name, 1, 1)

  if len(dllFiles) == 0
    throw "No executable found although Vim attempted to build the project!" . " " . g:OmniSharp_workspace_root
  endif

  return dllFiles[0]
endfunction

function! OmniSharp#actions#workspace#BuildSolution() abort
   echo "Building the .NET project..."

   let command = 'dotnet build' 
   let result = system('cd ' . g:OmniSharp_workspace_root . ' && ' . command)
endfunction

function! OmniSharp#actions#workspace#GetProjectInfoForFile() abort
  let current_dir = fnamemodify(expand("%:p"), ':h')
  let proj_dir = s:search_file_extension(current_dir, "csproj")
  let csproj_files = globpath(proj_dir, '**/*.csproj', 1, 1)

  if len(csproj_files) != 1
    throw "Invalid number of projects in the directory: " . len(csproj_files)
  endif

  let project_name = fnamemodify(csproj_files[0], ':t:r')
  let directory_path = fnamemodify(csproj_files[0], ':h')

  return {"name": project_name, "path": csproj_files[0], "projectdir": directory_path}
endfunction

function! OmniSharp#actions#workspace#GetNamespaceForFile() abort
    let file_name = fnamemodify(expand("%:p"), ':t')

    " evaluate namespace
    let proj_info = OmniSharp#actions#workspace#GetProjectInfoForFile()

    let newstr = substitute(expand("%:p"), proj_info.projectdir, '', '')
    let splitted = split(newstr, '/')
    let splitted = splitted[0:-2]

    " root dir
    if len(splitted) == 0
      return proj_info.name
    endif

    let ns = proj_info.name
    let ns = ns . "."

    for word in splitted
        let ns = ns . word . "."
    endfor

    " clear the last dot
    let ns = ns[0:len(ns) - 2]
    return ns
endfunction

" Searchs for given file extension and returns it's path
function s:search_file_extension(initialDir, extension)
  let current_dir = a:initialDir
  let found = 0
  let files = systemlist('ls ' . current_dir)
  while found == 0 && current_dir != '/'
    for f in files
      if f =~ a:extension
        let targetFile = f
        let found = 1
        return current_dir
      endif
    endfor
    let current_dir = fnamemodify(current_dir, ':h')
    let files = systemlist('ls ' . current_dir)
  endwhile
  return v:null
endfunction


" vim:et:sw=2:sts=2
