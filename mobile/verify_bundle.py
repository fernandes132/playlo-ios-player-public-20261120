"""Verify the actual installed-package resources, not only the source directory."""
from pathlib import Path,PurePosixPath
import hashlib,json,sys,zipfile
def verify(file):
    file=Path(file)
    prefix='assets/Shared/Web/' if file.suffix=='.apk' else 'Payload/Playlo.app/Shared/Web/'
    with zipfile.ZipFile(file) as archive:
        assert archive.testzip() is None,'Damaged archive'
        manifest=json.loads(archive.read(prefix+'bundle-manifest.json'))
        assert (manifest.get('bundled') or manifest.get('localTest')) and len(set(manifest['games']))==34 and manifest['studio']
        if manifest.get('defaultNetwork')=='live':
            config=json.loads(archive.read(prefix+'app-online.json'))
            shell=json.loads(archive.read(prefix.removesuffix('Web/')+'app-shell.json'))
            assert config['apiOrigin']==config['identityOrigin']==shell['origin']==manifest['apiOrigin']==manifest['identityOrigin']
            assert config['apiOrigin']=='https://playlo-social-games.fernandofrederiksen2.chatgpt.site'
            assert manifest['localTest'] is False and manifest['websitePublished'] is True
        assert {'bomb-pass','bordgenoten','haunted-escape','lava-run','rendier-express','schoorsteen-sprint'}<=set(manifest['games'])
        files=manifest['files'];assert files and len({f['path'] for f in files})==len(files)
        for entry in files:
            path=PurePosixPath(entry['path']);assert not path.is_absolute() and '..' not in path.parts
            data=archive.read(prefix+path.as_posix());assert len(data)==entry['bytes'] and hashlib.sha256(data).hexdigest()==entry['sha256'],str(path)
        expected={entry['path'] for entry in files}|{'bundle-manifest.json'}
        actual={n[len(prefix):] for n in archive.namelist() if n.startswith(prefix) and not n.endswith('/')}
        assert actual==expected,'Package contains missing or stale bundle resources'
    return {'file':file.name,'version':manifest['version'],'games':len(manifest['games']),'studio':True,'embeddedFiles':len(files),'allFileHashesMatch':True,'sha256':hashlib.sha256(file.read_bytes()).hexdigest()}
if __name__=='__main__':print(json.dumps(verify(sys.argv[1]),indent=2))
