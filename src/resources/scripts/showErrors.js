// !!!! important to use a closure here - otherwise script will pollute global scope and net being re-entrant
{
    const firstInvalid = document.querySelector('[invalid]');
    if(firstInvalid){
        firstInvalid.scrollIntoView({block: "end", inline: "nearest", behavior:"smooth"});
    }
}
