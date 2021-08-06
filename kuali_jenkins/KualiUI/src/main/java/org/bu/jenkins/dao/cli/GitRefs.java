package org.bu.jenkins.dao.cli;

import java.util.List;

import org.bu.jenkins.util.CaseInsensitiveEnvironment;
import org.bu.jenkins.util.NamedArgs;
import org.bu.jenkins.util.StringToList;
import org.bu.jenkins.util.logging.LoggingStarterImpl;

/**
 * Uses the system command line to make a git call for a listing of all tags or all branches from the specified 
 * remote git repository. CLI output is returned as a list.
 * 
 * @author wrh
 *
 */
public class GitRefs extends GitCommandLineAdapter {

	public GitRefs(RuntimeCommand cmd) {
		super(cmd);
	}

	@Override
	public String[] getGitCommandParts() {
		return new String[] {
			"git",
			"-c",
			"core.askpass=true",
			"ls-remote",
			"-" + refType.categorySwitch(),
			remoteUrl				
		};
	}

	@Override
	public List<String> getFilteredOutput() {
		final String category = String.format("refs/%s/", refType.category());
		return new StringToList(printGitOutput(refType)) {
			@Override public String filter(String ref) {
				if(ref.contains(category)) {
					return ref.split(category)[1].strip();
				}
				else if(cmd.hasError()) {
					return ref;
				}
				return null;
			}
		}.getList();
	}
	
	public static void main(String[] args) {
		NamedArgs namedargs = new NamedArgs(new LoggingStarterImpl(new CaseInsensitiveEnvironment()), args);
		
		GitRefs refs = new GitRefs(RuntimeCommand.getCommandInstance());
		
		refs.setRefType(RefType.BRANCH);
		refs.setSshKeyPath(namedargs.get("ssh-key", "C:\\Users\\wrh\\.ssh\\bu_github_id_coi_rsa"));
		refs.setPersonalAccessToken(namedargs.get("pat"));
		refs.setRemoteUrl(namedargs.get("remote-url", "git@github.com:bu-ist/kuali-research-coi.git"));
		refs.setUser(namedargs.get("user", "bu-ist-user"));
		refs.setDryrun(Boolean.valueOf(namedargs.get("dryrun", "false")));
		
		for(String tag : refs.getOutputList()) {
			System.out.println(tag);
		}
		
		refs.setRefType(RefType.TAG);
		
		for(String branch : refs.getOutputList()) {
			System.out.println(branch);
		}
		
	}
}
